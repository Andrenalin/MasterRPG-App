// @copyright André Trettin

import Foundation
import Network
import Security
import os.log
import CoreRPG

protocol ConnectionControllable: Sendable {
    var id: UUID { get }

    func startConnection() async
    func cancel() async

    func request(type: GameMessageType, with content: MessageMapper?) async
    func response(type: GameMessageType, with content: MessageMapper?) async
    func request(type: GameMessageType, encodedContent: Data?) async
    func response(type: GameMessageType, encodedContent: Data?) async
}

protocol ConnectionControllerDelegate: Sendable & AnyObject {
    func received(data: Data?, for id: ConnectionController.ID) async
    /// `isAuthenticationFailure` distinguishes a TLS/PSK (passcode) rejection
    /// from an ordinary transport-layer failure (Wi-Fi drop, timeout,
    /// unreachable peer) — only the former is evidence of a bad-passcode
    /// guess. A conformer that doesn't need the distinction can ignore it;
    /// the throttle-aware conformers (`PlayerNetworkController`,
    /// `MasterNetworkController`) use it to avoid penalizing a legitimate
    /// peer's ordinary reconnect retry. See CODE_AUDIT_Reconnect §6.1.
    func failed(with error: String?, isAuthenticationFailure: Bool, for id: ConnectionController.ID) async
    func lostConnection(for id: ConnectionController.ID) async
    func readyConnection(for id: ConnectionController.ID) async
}

actor ConnectionController: Identifiable {
    nonisolated let id: UUID
    private let connection: NWConnection
    // NWConnection needs a dispatch queue; callbacks hop from it into the actor.
    private let queue = DispatchQueue(label: BundleIds.app("ConnectionController"))
    private weak var delegate: (any ConnectionControllerDelegate)?
    private var receiveTask: Task<Void, Never>?
    /// Set the moment `connectionFailed(message:isAuthenticationFailure:)`
    /// reports a terminal outcome to the delegate. `cancel()` (called from
    /// every failure path) always produces a later `.cancelled` state
    /// callback from `NWConnection`; without this guard that `.cancelled`
    /// would *also* call `lostConnection()`, delivering two independent
    /// terminal-outcome delegate calls — `failed` then `lostConnection` — for
    /// one underlying failure, racing `ConnectionThrottleTracker`'s
    /// `resolve(id:succeeded:)` against its own `clear(id:)` with no ordering
    /// guarantee between them. If `clear` won that race, the failure was
    /// silently dropped from the throttle's tally. One instance only ever
    /// reports one terminal outcome, so this never needs to reset. See
    /// CODE_AUDIT_Reconnect §3.1.
    private var terminalOutcomeReported = false
    /// Set by an external `cancel()` (the owner tearing the connection down on purpose). The
    /// pending `receiveMessage` completes afterwards with a cancellation error that must not be
    /// reported as a failure of its own. See CODE_AUDIT_15 §3.6.
    private var wasCancelledLocally = false
    /// Consumes `NWConnection` state updates in the order they were delivered.
    private var stateTask: Task<Void, Never>?

    init(id: UUID, endpoint: NWEndpoint, passcode: String, delegate: ConnectionControllerDelegate) {
        self.id = id
        self.connection = NWConnection.connection(endpoint: endpoint, passcode: passcode)
        self.delegate = delegate
        Logger.connectionController.debug("Connection: \(id.uuidString, privacy: .public) Init endpoint (\(NWParameters.passcodeCheck(passcode), privacy: .private))")
    }

    init(id: UUID, connection: NWConnection, delegate: ConnectionControllerDelegate) {
        self.id = id
        self.connection = connection
        self.delegate = delegate
        Logger.connectionController.debug("Connection: \(id.uuidString, privacy: .public) Init connection")
    }

    deinit {
        // Owners may drop connections without an explicit cancel() (e.g. resetConnections).
        receiveTask?.cancel()
        stateTask?.cancel()
        connection.cancel()
    }
}

extension ConnectionController: ConnectionControllable {

    func sendResponse(data: MessageMapper?) {
        response(type: .gameData, with: data)
    }

    func request(with content: MessageMapper?) {
        request(type: .gameData, with: content)
    }

    func startConnection() {
        let uuid = id.uuidString
        Logger.connectionController.debug("Connection: \(uuid, privacy: .public) Start")

        // One `Task` per state change gave no ordering guarantee (`.ready` could be processed
        // after `.failed`/`.cancelled`); a single consumer of an `AsyncStream` keeps the order.
        // See CODE_AUDIT_15 §3.6.
        let (states, continuation) = AsyncStream.makeStream(of: NWConnection.State.self)
        connection.stateUpdateHandler = { newState in
            continuation.yield(newState)
            if case .cancelled = newState { continuation.finish() }
        }
        stateTask = Task { [weak self] in
            for await state in states {
                guard let self else { break }
                await self.stateChanged(state)
            }
        }
        connection.start(queue: queue)
    }

    func cancel() {
        wasCancelledLocally = true
        teardown()
    }

    func request(type: GameMessageType, with content: MessageMapper?) {
        request(type: type, encodedContent: content?.encodeData())
    }

    func response(type: GameMessageType, with content: MessageMapper?) {
        response(type: type, encodedContent: content?.encodeData())
    }

    func request(type: GameMessageType, encodedContent: Data?) {
        let uuid = id.uuidString
        Logger.connectionController.debug("Connection: \(uuid, privacy: .public) Send request")
        let message = NWProtocolFramer.Message(gameMessageType: type)
        let context = NWConnection.ContentContext(identifier: "PlayerRequest", metadata: [message])
        send(content: encodedContent, context: context)
    }

    func response(type: GameMessageType, encodedContent: Data?) {
        let uuid = id.uuidString
        Logger.connectionController.debug("Connection: \(uuid, privacy: .public) Send response")
        let message = NWProtocolFramer.Message(gameMessageType: type)
        let context = NWConnection.ContentContext(identifier: "MasterResponse", metadata: [message])
        send(content: encodedContent, context: context)
    }

    /// `.idempotent` completion never invokes its handler at all, so the app
    /// was never told whether a write actually reached the peer — a
    /// mid-flight failure (a Wi-Fi drop, backgrounding, a peer going out of
    /// range) silently lost that specific message with no signal to retry
    /// it and no way to select which in-flight message(s) were affected.
    /// `.contentProcessed` surfaces a failure through the same
    /// `connectionFailed` path a receive-side error already uses, so the
    /// delegate learns the connection is dead instead of nothing ever
    /// finding out. See CODE_AUDIT_Network §5.5.
    private func send(content: Data?, context: NWConnection.ContentContext) {
        connection.send(
            content: content,
            contentContext: context,
            isComplete: true,
            completion: .contentProcessed { [weak self] error in
                guard let error else { return }
                Task { await self?.sendFailed(error: error) }
            }
        )
    }

    private func sendFailed(error: NWError) async {
        // A send still in flight when the owner cancelled completes with an error too.
        guard !wasCancelledLocally else { return }
        let uuid = id.uuidString
        Logger.connectionController.error("Connection: \(uuid, privacy: .public) Send failed \(error.localizedDescription, privacy: .public)")
        teardown()
        await connectionFailed(message: error.localizedDescription, isAuthenticationFailure: Self.isAuthenticationFailure(error))
    }
}
private extension ConnectionController {
    /// Stops receiving and cancels the connection without marking the cancel as the owner's.
    func teardown() {
        receiveTask?.cancel()
        receiveTask = nil
        connection.cancel()
    }

    func stateChanged(_ newState: NWConnection.State) async {
        let uuid = id.uuidString

        switch newState {
        case .ready:
            Logger.connectionController.debug("Connection: \(uuid, privacy: .public) Ready")
            // A late `.ready` after a terminal outcome or a local cancel must not arm a receive.
            guard !terminalOutcomeReported, !wasCancelledLocally else { return }
            startReceiveLoop()
            await connectionReady()

        case let .failed(error):
            Logger.connectionController.debug("Connection: \(uuid, privacy: .public) Failed \(error.localizedDescription, privacy: .public)")
            teardown()
            await connectionFailed(message: error.localizedDescription, isAuthenticationFailure: Self.isAuthenticationFailure(error))

        case .cancelled:
            Logger.connectionController.debug("Connection: \(uuid, privacy: .public) Cancelled")
            // Mirrors `cancel()`: without this, a receive callback still
            // pending inside `receiveLoop` fires once more with a
            // cancellation error after teardown was already reported,
            // re-entering `process()`/`connectionFailed()` for the same
            // underlying event. See CODE_AUDIT_Network §5.9.
            receiveTask?.cancel()
            receiveTask = nil
            // Only report a fresh loss if this instance hasn't already
            // reported a terminal outcome via `connectionFailed` — see
            // `terminalOutcomeReported`'s own doc. A `.cancelled` that
            // follows an external `cancel()` (e.g. `stop()`'s own teardown,
            // never preceded by a reported failure) still reports normally.
            guard !terminalOutcomeReported else { return }
            terminalOutcomeReported = true
            await lostConnection()

        case let .waiting(error):
            // A rejected handshake (wrong code: `-9820 bad MAC`, unknown identity: `-9864`)
            // surfaces as `.waiting(.tls)`, never as `.failed`: the framework keeps the
            // connection "waiting" to retry. The passcode cannot change between retries, so it is
            // terminal here; other waiting reasons (no route, permission pending) stay
            // transient. Without this a wrong code only showed up as a 12 s join timeout.
            guard case .tls = error else { break }
            Logger.connectionController.debug("Connection: \(uuid, privacy: .public) Handshake rejected \(error.localizedDescription, privacy: .public)")
            teardown()
            // Classified like the `.failed` path: a transient TLS close/abort on flaky
            // Wi-Fi must not count toward the wrong-code lockout. See CODE_AUDIT_18 §5.18.
            await connectionFailed(message: error.localizedDescription, isAuthenticationFailure: Self.isAuthenticationFailure(error))

        default:
            break
        }
    }

    func startReceiveLoop() {
        guard receiveTask == nil else { return }
        receiveTask = Task { [weak self] in
            guard let self else { return }
            await self.receiveLoop()
        }
    }

    func receiveLoop() async {
        while !Task.isCancelled {
            let shouldContinue = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                connection.receiveMessage { [weak self] content, context, _, error in
                    guard let self else {
                        continuation.resume(returning: false)
                        return
                    }
                    Task {
                        await self.process(content: content, context: context, error: error)
                        continuation.resume(returning: error == nil)
                    }
                }
            }
            if !shouldContinue { break }
        }
    }

    func process(content: Data?, context: NWConnection.ContentContext?, error: Error?) async {
        // The receive that was pending when the owner cancelled completes with an error (or
        // EOF): the teardown is already being reported through `.cancelled`.
        guard !wasCancelledLocally else { return }
        guard error == nil else {
            let uuid = id.uuidString
            Logger.connectionController.error("Connection: \(uuid, privacy: .public) Error \(error?.localizedDescription ?? "", privacy: .public)")
            teardown()
            let isAuthenticationFailure = (error as? NWError).map(Self.isAuthenticationFailure) ?? false
            await connectionFailed(message: error?.localizedDescription ?? "", isAuthenticationFailure: isAuthenticationFailure)
            return
        }
        guard content != nil else {
            // No error, but no content either: the standard `NWConnection`
            // idiom for a graceful peer half-close (EOF), not an ordinary
            // unrecognized message — a routine occurrence on every clean
            // disconnect (player quits, master stops a player, app
            // backgrounds). Previously this fell into the same
            // log-and-continue branch as a genuinely foreign/garbage
            // message, so the delegate was never told the connection died,
            // and `receiveLoop` re-armed `receiveMessage` in a tight,
            // non-yielding cycle since a closed stream's completion replays
            // instantly. See CODE_AUDIT_Network §5.6.
            let uuid = id.uuidString
            Logger.connectionController.debug("Connection: \(uuid, privacy: .public) Peer closed the connection")
            teardown()
            // A graceful peer half-close is never evidence of a bad passcode.
            await connectionFailed(message: "Peer closed the connection", isAuthenticationFailure: false)
            return
        }
        guard let gameMessage = context?.protocolMetadata(definition: GameProtocol.definition) as? NWProtocolFramer.Message else {
            let uuid = id.uuidString
            Logger.connectionController.error("Connection: \(uuid, privacy: .public) Message is not from MasterRPG")
            return
        }
        await receivedMessage(content: content, message: gameMessage)
    }
}

extension ConnectionController {
    func lostConnection() async {
        let uuid = id.uuidString
        Logger.connectionController.debug("Connection: \(uuid, privacy: .public) Lost")
        await delegate?.lostConnection(for: id)
    }

    func connectionReady() async {
        let uuid = id.uuidString
        Logger.connectionController.debug("Connection: \(uuid, privacy: .public) Established")
        await delegate?.readyConnection(for: id)
    }

    func connectionFailed(message: String, isAuthenticationFailure: Bool) async {
        let uuid = id.uuidString
        Logger.connectionController.debug("Connection: \(uuid, privacy: .public) Failed \(message, privacy: .public)")
        // See `terminalOutcomeReported`'s own doc — the `.cancelled` that
        // `cancel()` (called by every path that reaches this) always
        // produces afterward must not also report `lostConnection()`.
        guard !terminalOutcomeReported else { return }
        terminalOutcomeReported = true
        await delegate?.failed(with: message, isAuthenticationFailure: isAuthenticationFailure, for: id)
    }

    /// A TLS/PSK (passcode) rejection surfaces as `NWError.tls` — the only
    /// case a wrong passcode can plausibly produce, since the PSK identity
    /// itself is fixed and only the derived key differs. Every other case
    /// (`.posix`, `.dns`, `.quic`) is a transport-layer failure (Wi-Fi drop,
    /// timeout, unreachable/firewalled peer) that says nothing about whether
    /// the passcode was even checked yet. See CODE_AUDIT_Reconnect §6.1.
    /// TLS statuses that end a handshake for transport reasons (the connection closed,
    /// aborted or timed out), not because the join code was wrong. See CODE_AUDIT_18 §5.18.
    nonisolated static let transientTLSStatuses: Set<OSStatus> = [
        errSSLClosedGraceful,
        errSSLClosedAbort,
        errSSLClosedNoNotify,
        errSSLConnectionRefused,
        errSSLWouldBlock,
        errSSLNetworkTimeout
    ]

    nonisolated static func isAuthenticationFailure(_ error: NWError) -> Bool {
        guard case let .tls(status) = error else { return false }
        return !transientTLSStatuses.contains(status)
    }

    func receivedMessage(content: Data?, message: NWProtocolFramer.Message) async {
        guard message.gameMessageType == .gameData else {
            let uuid = id.uuidString
            Logger.connectionController.error("Connection: \(uuid, privacy: .public) Invalid message type")
            return
        }
        await delegate?.received(data: content, for: id)
    }
}

public extension Logger {
    static let connectionController = Logger(subsystem: subsystem, category: "ConnectionController")
}
