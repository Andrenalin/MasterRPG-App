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

    private(set) var state: NetworkState = .cancelled

    @ObservationIgnored private var monitorTask: Task<Void, Never>?
    @ObservationIgnored private var networkTask: Task<Void, Never>?
    weak var delegate: (any ListenerManagerDelegate)?

    init(name: String, supporterTier: SupporterTier = .none, serviceType: GameServiceType) {
        self.name = name
        self.supporterTier = supporterTier
        self.serviceType = serviceType
        Logger.listenerController.debug("ListenerManager: Init \(name, privacy: .public)")
    }

    isolated deinit {
        cancelTasks()
        let listenerName = name
        Logger.listenerController.debug("ListenerManager: Deinit \(listenerName, privacy: .public)")
    }

    func startListening() {
        guard state != .waitingForConnection && state != .connecting else { return }
        cancelTasks()
        state = .connecting

        let controller = ListenerServerController(name: name, supporterTier: supporterTier, serviceType: serviceType)

        monitorTask = Task { @MainActor [weak self] in
            for await event in controller.events {
                await self?.handle(event)
            }
        }

        networkTask = Task { [weak self] in
            do {
                try await controller.run()
            } catch is CancellationError {
                await MainActor.run { self?.state = .cancelled }
            } catch {
                Logger.listenerController.error("ListenerManager: Error \(error.localizedDescription, privacy: .public)")
                await MainActor.run { self?.state = .stopped }
            }
        }
    }

    func stopListening() {
        cancelTasks()
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
    fileprivate let events: AsyncStream<ListenerEvent>
    private let continuation: AsyncStream<ListenerEvent>.Continuation
    private let name: String
    private let supporterTier: SupporterTier
    private let serviceType: GameServiceType

    init(name: String, supporterTier: SupporterTier = .none, serviceType: GameServiceType) {
        self.name = name
        self.supporterTier = supporterTier
        self.serviceType = serviceType
        (self.events, self.continuation) = AsyncStream.makeStream(of: ListenerEvent.self)
    }

    func run() async throws {
        let listener = try NWListener(using: NWParameters(passcode: GameSecurity.passcode))
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

        listener.start(queue: .main)

        try await withTaskCancellationHandler {
            try await Task.sleep(for: .seconds(24*60*60))
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
