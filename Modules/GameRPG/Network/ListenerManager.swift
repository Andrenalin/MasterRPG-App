// @copyright André Trettin

import Network
import os.log
import CoreRPG
import Foundation

extension NWTXTRecord {
    static let supporterTierKey = "tier"
    /// Identifies the game session a service belongs to. See CODE_AUDIT_Join §5.2.
    static let sessionKey = "session"
}

fileprivate enum ListenerEvent: Sendable {
    case ready
    case waiting(NWError)
    case failed(NWError)
    case cancelled
    case newConnection(NWConnection)
}

protocol ListenerManagerDelegate: AnyObject, Sendable {
    /// The listener actually reached `.ready` — the only point `listenerStatus` should
    /// be derived from as "really running", rather than the caller assuming success
    /// right after calling `startListening()`. See CODE_AUDIT_17 §5.22.
    func listenerReady() async
    func listenerCancelled() async
    func listenerNewConnection(_ connection: NWConnection) async
    /// The listener is up but can't accept yet (local-network permission prompt, no
    /// interface). See CODE_AUDIT_18 §5.15.
    func listenerWaiting(_ error: NWError) async
}

extension ListenerManagerDelegate {
    func listenerWaiting(_ error: NWError) async {}
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
    let sessionId: String?

    private(set) var state: NetworkState = .cancelled

    @ObservationIgnored private var monitorTask: Task<Void, Never>?
    @ObservationIgnored private var networkTask: Task<Void, Never>?
    weak var delegate: (any ListenerManagerDelegate)?

    init(name: String, supporterTier: SupporterTier = .none, serviceType: GameServiceType, passcode: String, sessionId: String? = nil) {
        self.name = name
        self.supporterTier = supporterTier
        self.serviceType = serviceType
        self.passcode = passcode
        self.sessionId = sessionId
        Logger.listenerController.debug("ListenerManager: Init \(name, privacy: .private)")
    }

    isolated deinit {
        cancelTasks()
        let listenerName = name
        Logger.listenerController.debug("ListenerManager: Deinit \(listenerName, privacy: .private)")
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

        let controller = ListenerServerController(name: name, supporterTier: supporterTier, serviceType: serviceType, passcode: passcode, sessionId: sessionId)

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
                // `run()` throwing (e.g. `NWListener(using:)` itself failing) previously
                // only set `state` here and never told the delegate, while the caller had
                // already set `listenerStatus = .running` right after starting — the GM
                // saw a healthy game while nobody could join, and the restart-with-backoff
                // wired to `listenerCancelled()` never ran for this failure. Route it
                // through the same delegate path as the `.failed` event. See
                // CODE_AUDIT_17 §5.22.
                await self.delegate?.listenerCancelled()
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
            await delegate?.listenerReady()
        case .waiting(let error):
            Logger.listenerController.debug("ListenerManager: Waiting \(error.localizedDescription, privacy: .public)")
            await delegate?.listenerWaiting(error)
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
    private let sessionId: String?
    // NWListener needs a dispatch queue for its callbacks, which immediately
    // hop into this actor via Task { await self... } below — a dedicated
    // background queue matches ConnectionController's own NWConnection
    // wrapper rather than routing through the main queue. See CODE_AUDIT_9
    // §3.4.
    private let queue = DispatchQueue(label: BundleIds.app("ListenerServerController"))

    init(name: String, supporterTier: SupporterTier = .none, serviceType: GameServiceType, passcode: String, sessionId: String? = nil) {
        self.name = name
        self.supporterTier = supporterTier
        self.serviceType = serviceType
        self.passcode = passcode
        self.sessionId = sessionId
        (self.events, self.continuation) = AsyncStream.makeStream(of: ListenerEvent.self)
    }

    func run() async throws {
        let passcodeCheck = NWParameters.passcodeCheck(passcode)
        Logger.listenerController.debug("ListenerManager: Listening (\(passcodeCheck, privacy: .private))")
        let listener = try NWListener(using: NWParameters(passcode: passcode))
        var txtEntries = [NWTXTRecord.supporterTierKey: String(supporterTier.rawValue)]
        if let sessionId {
            txtEntries[NWTXTRecord.sessionKey] = sessionId
        }
        listener.service = NWListener.Service(name: Self.advertisedName(from: name), type: serviceType.serviceName, txtRecord: NWTXTRecord(txtEntries))
        defer {
            listener.cancel()
            continuation.finish()
        }

        // Yield straight into the ordered event stream from the listener's queue: one `Task`
        // per callback gave no ordering guarantee (`.ready` could be handled after
        // `.failed`/`.cancelled`, a connection before `.ready`), and since CODE_AUDIT_17 §5.22
        // that order drives `listenerStatus`. Same pattern as `ConnectionController`.
        // See CODE_AUDIT_18 §3.16.
        let continuation = self.continuation
        let listenerName = name
        let serviceName = serviceType.serviceName
        listener.stateUpdateHandler = { state in
            Self.yield(state, to: continuation, listenerName: listenerName, serviceName: serviceName)
        }
        listener.newConnectionHandler = { connection in
            continuation.yield(.newConnection(connection))
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

    /// DNS-SD instance names are limited to 63 UTF-8 bytes, and an empty name is invalid. The
    /// adventure title is arbitrary user text, so it is trimmed and cut on a character boundary
    /// rather than risking a listener that refuses to start. See CODE_AUDIT_Join §5.10.
    static func advertisedName(from name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "MasterRPG" : trimmed
        var result = ""
        var byteCount = 0
        for character in base {
            let characterBytes = String(character).utf8.count
            guard byteCount + characterBytes <= 63 else { break }
            result.append(character)
            byteCount += characterBytes
        }
        return result
    }

    private static func yield(
        _ state: NWListener.State,
        to continuation: AsyncStream<ListenerEvent>.Continuation,
        listenerName: String,
        serviceName: String
    ) {
        switch state {
        case .ready:
            Logger.listenerController.debug("ListenerManager: \(listenerName, privacy: .private) ready on \(serviceName, privacy: .private)")
            continuation.yield(.ready)
        case .waiting(let error):
            continuation.yield(.waiting(error))
        case .failed(let error):
            Logger.listenerController.error("ListenerManager: \(listenerName, privacy: .private) failed \(error.localizedDescription, privacy: .public)")
            continuation.yield(.failed(error))
            continuation.finish()
        case .cancelled:
            continuation.yield(.cancelled)
            continuation.finish()
        default:
            break
        }
    }
}

public extension Logger {
    static let listenerController = Logger(subsystem: subsystem, category: "ListenerController")
}
