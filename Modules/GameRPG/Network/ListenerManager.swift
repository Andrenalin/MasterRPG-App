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
    case newConnection(GameConnection)
}

protocol ListenerManagerDelegate: AnyObject, Sendable {
    /// The listener actually reached `.ready` — the only point `listenerStatus` should
    /// be derived from as "really running", rather than the caller assuming success
    /// right after calling `startListening()`. See CODE_AUDIT_17 §5.22.
    func listenerReady() async
    func listenerCancelled() async
    func listenerNewConnection(_ connection: GameConnection) async
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
                // `run()` throwing (e.g. `GameListener(for:using:)` itself failing) previously
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
    fileprivate let events: AsyncStream<ListenerEvent>
    private let continuation: AsyncStream<ListenerEvent>.Continuation
    private let name: String
    private let supporterTier: SupporterTier
    private let serviceType: GameServiceType
    private let passcode: String
    private let sessionId: String?

    init(name: String, supporterTier: SupporterTier = .none, serviceType: GameServiceType, passcode: String, sessionId: String? = nil) {
        self.name = name
        self.supporterTier = supporterTier
        self.serviceType = serviceType
        self.passcode = passcode
        self.sessionId = sessionId
        (self.events, self.continuation) = AsyncStream.makeStream(of: ListenerEvent.self)
    }

    /// Listens until the calling task is cancelled (then throws `CancellationError`) or the
    /// listener ends. Runs on the structured `GameListener`, which needs no dispatch queue and
    /// no keep-alive loop. See CODE_AUDIT_19 §4.2.
    func run() async throws {
        let passcodeCheck = NWParameters.passcodeCheck(passcode)
        Logger.listenerController.debug("ListenerManager: Listening (\(passcodeCheck, privacy: .private))")
        var txtEntries = [NWTXTRecord.supporterTierKey: String(supporterTier.rawValue)]
        if let sessionId {
            txtEntries[NWTXTRecord.sessionKey] = sessionId
        }
        let listener = try GameListener(
            for: .bonjour(name: Self.advertisedName(from: name), type: serviceType.serviceName, txtRecord: NWTXTRecord(txtEntries)),
            using: GameNetworkParameters.builder(passcode: passcode)
        )
        let continuation = continuation
        defer { continuation.finish() }

        // Yield straight into the ordered event stream: one `Task` per callback gave no ordering
        // guarantee (`.ready` could be handled after `.failed`/`.cancelled`, a connection before
        // `.ready`), and since CODE_AUDIT_17 §5.22 that order drives `listenerStatus`. Same
        // pattern as `ConnectionController`. See CODE_AUDIT_18 §3.16.
        let listenerName = name
        let serviceName = serviceType.serviceName
        listener.onStateUpdate { _, state in
            Self.yield(state, to: continuation, listenerName: listenerName, serviceName: serviceName)
        }

        // The handler hands each connection to `ListenerManager` and returns: an accepted
        // connection lives as long as its `ConnectionController` holds it, not as long as this
        // handler or the listener runs. Cancelling the listener stops accepting new connections
        // and keeps the accepted ones, as `NWListener` did (the player's reconnect listener is
        // retired while its connection stays up).
        do {
            try await listener.run { connection in
                continuation.yield(.newConnection(connection))
            }
        } catch {
            try Task.checkCancellation()
            // Reported as the terminal event, not thrown: `ListenerManager` would otherwise call
            // `listenerCancelled()` for the error and again for the `.failed` state. The stream
            // finishes on the first terminal event, so whichever comes second is dropped.
            Self.yield(.failed(error as? NWError ?? .posix(.EIO)), to: continuation, listenerName: listenerName, serviceName: serviceName)
            return
        }
        // `run` returns normally when its task is cancelled; `ListenerManager` tells a
        // cancellation apart from a failure by the error.
        try Task.checkCancellation()
        Self.yield(.cancelled, to: continuation, listenerName: listenerName, serviceName: serviceName)
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
        _ state: GameListener.State,
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
