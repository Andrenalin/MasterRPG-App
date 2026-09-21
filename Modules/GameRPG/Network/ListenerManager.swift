// @copyright André Trettin

import Network
import os.log
import CoreRPG
import Foundation

extension NWTXTRecord {
    static let supporterTierKey = "tier"
}

fileprivate enum ListenerEvent: Sendable {
    case ready
    case failed(NWError)
    case cancelled
    case newConnection(NWConnection)
}

protocol ListenerManagerDelegate: AnyObject, Sendable {
    func listenerCancelled() async
    func listenerNewConnection(_ connection: NWConnection) async
}

/// Testable surface for ListenerManager — lets tests inject a mock.
protocol ListenerManaging: AnyObject, Sendable {
    @MainActor func startListening()
    @MainActor func stopListening()
}

@Observable @MainActor
final class ListenerManager: ListenerManaging {
    let serviceType: GameServiceType
    let name: String
    let supporterTier: SupporterTier
    let passcode: String

    private(set) var state: NetworkState = .cancelled

    @ObservationIgnored private var monitorTask: Task<Void, Never>?
    @ObservationIgnored private var networkTask: Task<Void, Never>?
    weak var delegate: (any ListenerManagerDelegate)?

    init(name: String, supporterTier: SupporterTier = .none, serviceType: GameServiceType, passcode: String) {
        self.name = name
        self.supporterTier = supporterTier
        self.serviceType = serviceType
        self.passcode = passcode
        Logger.listenerController.debug("ListenerManager: Init \(name, privacy: .public)")
    }

    isolated deinit {
        cancelTasks()
        let listenerName = name
        Logger.listenerController.debug("ListenerManager: Deinit \(listenerName, privacy: .public)")
    }

    /// Identifies the current listener run. A cancelled run's tasks resume later and must not
    /// write their outcome over the state of the run (or the `stopListening()`) that replaced
    /// them. See CODE_AUDIT_15 §3.7.
    private var runGeneration = 0

    func startListening() {
        guard state != .waitingForConnection && state != .connecting else { return }
        cancelTasks()
        runGeneration += 1
        let generation = runGeneration
        state = .connecting

        let controller = ListenerServerController(name: name, supporterTier: supporterTier, serviceType: serviceType, passcode: passcode)

        monitorTask = Task { @MainActor [weak self] in
            for await event in controller.events {
                guard let self, self.runGeneration == generation else { return }
                await self.handle(event)
            }
        }

        // This `Task` literal is written directly inside `startListening()`'s body, so —
        // like `monitorTask` above — it inherits this @MainActor class's isolation; no
        // `MainActor.run` wrapper needed to set `state` after the `await` resumes.
        networkTask = Task { [weak self] in
            do {
                try await controller.run()
            } catch is CancellationError {
                guard let self, self.runGeneration == generation else { return }
                self.state = .cancelled
            } catch {
                Logger.listenerController.error("ListenerManager: Error \(error.localizedDescription, privacy: .public)")
                guard let self, self.runGeneration == generation else { return }
                self.state = .stopped
            }
        }
    }

    func stopListening() {
        cancelTasks()
        runGeneration += 1
        state = .stopped
    }

    private func cancelTasks() {
        networkTask?.cancel()
        networkTask = nil
        monitorTask?.cancel()
        monitorTask = nil
    }

    private func handle(_ event: ListenerEvent) async {
        switch event {
        case .ready:
            state = .waitingForConnection
        case .failed(let error):
            Logger.listenerController.error("ListenerManager: Failed \(error.localizedDescription, privacy: .public)")
            state = .stopped
            await delegate?.listenerCancelled()
        case .cancelled:
            state = .cancelled
            await delegate?.listenerCancelled()
        case .newConnection(let connection):
            await delegate?.listenerNewConnection(connection)
        }
    }
}

actor ListenerServerController {
    /// How long each individual sleep in `run()`'s keep-alive loop lasts —
    /// not a listener timeout. See CODE_AUDIT §9.12.
    private static let keepAliveInterval: Duration = .seconds(24 * 60 * 60)

    fileprivate let events: AsyncStream<ListenerEvent>
    private let continuation: AsyncStream<ListenerEvent>.Continuation
    private let name: String
    private let supporterTier: SupporterTier
    private let serviceType: GameServiceType
    private let passcode: String
    // NWListener needs a dispatch queue for its callbacks, which immediately
    // hop into this actor via Task { await self... } below — a dedicated
    // background queue matches ConnectionController's own NWConnection
    // wrapper rather than routing through the main queue. See CODE_AUDIT_9
    // §3.4.
    private let queue = DispatchQueue(label: "de.andretrettin.MasterRPG.ListenerServerController")

    init(name: String, supporterTier: SupporterTier = .none, serviceType: GameServiceType, passcode: String) {
        self.name = name
        self.supporterTier = supporterTier
        self.serviceType = serviceType
        self.passcode = passcode
        (self.events, self.continuation) = AsyncStream.makeStream(of: ListenerEvent.self)
    }

    func run() async throws {
        let listener = try NWListener(using: NWParameters(passcode: passcode))
        let txtRecord = NWTXTRecord([NWTXTRecord.supporterTierKey: String(supporterTier.rawValue)])
        listener.service = NWListener.Service(name: name, type: serviceType.serviceName, txtRecord: txtRecord)
        defer {
            listener.cancel()
            continuation.finish()
        }

        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            Task { await self.handleState(state) }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            Task { await self.handleNewConnection(connection) }
        }

        listener.start(queue: queue)

        // `run()` only needs to stay suspended — actual listening is entirely
        // driven by `listener`'s own callbacks above — so this loops a bounded
        // sleep indefinitely rather than a single fixed-duration one. A single
        // `Task.sleep` here used to let `run()` return normally once it
        // elapsed, which tore the listener down (via the `defer` above)
        // without ever yielding a `.cancelled`/`.failed` event, so a session
        // hosted for more than a day would silently stop accepting
        // connections with no signal to `ListenerManager`. See CODE_AUDIT §3.1.
        try await withTaskCancellationHandler {
            while true {
                try await Task.sleep(for: Self.keepAliveInterval)
            }
        } onCancel: {
            listener.cancel()
        }
    }

    private func handleState(_ state: NWListener.State) {
        let listenerName = name
        let serviceName = serviceType.serviceName
        switch state {
        case .ready:
            Logger.listenerController.debug("ListenerManager: \(listenerName, privacy: .public) ready on \(serviceName, privacy: .public)")
            continuation.yield(.ready)
        case .failed(let error):
            Logger.listenerController.error("ListenerManager: \(listenerName, privacy: .public) failed \(error.localizedDescription, privacy: .public)")
            continuation.yield(.failed(error))
            continuation.finish()
        case .cancelled:
            continuation.yield(.cancelled)
            continuation.finish()
        default:
            break
        }
    }

    private func handleNewConnection(_ connection: NWConnection) {
        continuation.yield(.newConnection(connection))
    }
}

public extension Logger {
    static let listenerController = Logger(subsystem: subsystem, category: "ListenerController")
}
