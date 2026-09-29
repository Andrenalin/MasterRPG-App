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
    /// Released on teardown. A `GameConnection` has no `cancel()`: cancelling the task waiting in
    /// `receive()`/`send()` cancels it, and dropping the last reference closes it.
    private var connection: GameConnection?
    private weak var delegate: (any ConnectionControllerDelegate)?
    private var receiveTask: Task<Void, Never>?
    /// Sends run one at a time from `outbound`, in the order they were queued, so an awaited send
    /// never lets a later message overtake it through actor reentrancy.
    private var sendTask: Task<Void, Never>?
    private let outbound: AsyncStream<OutboundMessage>
    private let outboundContinuation: AsyncStream<OutboundMessage>.Continuation
    /// A message can arrive before the `.ready` state update is handled; the delegate still hears
    /// `readyConnection` first.
    private var readyReported = false
    /// Set the moment `connectionFailed(message:isAuthenticationFailure:)`
    /// reports a terminal outcome to the delegate. The teardown on every
    /// failure path can produce a later `.cancelled` state update from the
    /// connection; without this guard that `.cancelled` would *also* call
    /// `lostConnection()`, delivering two independent
    /// terminal-outcome delegate calls — `failed` then `lostConnection` — for
    /// one underlying failure, racing `ConnectionThrottleTracker`'s
    /// `resolve(id:succeeded:)` against its own `clear(id:)` with no ordering
    /// guarantee between them. If `clear` won that race, the failure was
    /// silently dropped from the throttle's tally. One instance only ever
    /// reports one terminal outcome, so this never needs to reset. See
    /// CODE_AUDIT_Reconnect §3.1.
    private var terminalOutcomeReported = false
    /// Set by an external `cancel()` (the owner tearing the connection down on purpose). The
    /// pending `receive()` completes afterwards with a cancellation error that must not be
    /// reported as a failure of its own. See CODE_AUDIT_15 §3.6.
    private var wasCancelledLocally = false
    /// Consumes connection state updates in the order they were delivered.
    private var stateTask: Task<Void, Never>?

    init(id: UUID, endpoint: NWEndpoint, passcode: String, delegate: ConnectionControllerDelegate) {
        self.init(id: id, connection: .game(to: endpoint, passcode: passcode), delegate: delegate)
        Logger.connectionController.debug("Connection: \(id.uuidString, privacy: .public) Init endpoint (\(NWParameters.passcodeCheck(passcode), privacy: .private))")
    }

    init(id: UUID, connection: GameConnection, delegate: ConnectionControllerDelegate) {
        self.id = id
        self.connection = connection
        self.delegate = delegate
        (outbound, outboundContinuation) = AsyncStream.makeStream(of: OutboundMessage.self)
        Logger.connectionController.debug("Connection: \(id.uuidString, privacy: .public) Init connection")
    }

    deinit {
        // Owners may drop connections without an explicit cancel() (e.g. resetConnections).
        // Cancelling the pending receive cancels the connection.
        receiveTask?.cancel()
        sendTask?.cancel()
        stateTask?.cancel()
        outboundContinuation.finish()
    }

    private struct OutboundMessage: Sendable {
        let type: GameMessageType
        let content: Data
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
        guard let connection, stateTask == nil else { return }
        let uuid = id.uuidString
        Logger.connectionController.debug("Connection: \(uuid, privacy: .public) Start")

        // One `Task` per state change gave no ordering guarantee (`.ready` could be processed
        // after `.failed`/`.cancelled`); a single consumer of an `AsyncStream` keeps the order.
        // See CODE_AUDIT_15 §3.6.
        let (states, continuation) = AsyncStream.makeStream(of: GameConnection.State.self)
        connection.onStateUpdate { _, newState in
            continuation.yield(newState)
            if case .cancelled = newState { continuation.finish() }
        }
        stateTask = Task { [weak self] in
            for await state in states {
                guard let self else { break }
                await self.stateChanged(state)
            }
        }
        // A `GameConnection` starts with its first `receive()`/`send()`, so the receive loop is
        // what establishes it. See CODE_AUDIT_19 §4.2.
        startReceiveLoop(on: connection)
        startSendLoop(on: connection)
    }

    func cancel() {
        wasCancelledLocally = true
        let wasStarted = stateTask != nil
        teardown()
        // Only a cancelled pending `receive()`/`send()` yields a `.cancelled` state update; a
        // connection released while idle closes without one. Report the loss either way, after
        // the caller's own bookkeeping as before; `terminalOutcomeReported` keeps it to one.
        guard wasStarted else { return }
        Task { await self.reportCancelled() }
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
        send(type: type, content: encodedContent)
    }

    func response(type: GameMessageType, encodedContent: Data?) {
        let uuid = id.uuidString
        Logger.connectionController.debug("Connection: \(uuid, privacy: .public) Send response")
        send(type: type, content: encodedContent)
    }

    /// Every send reports its outcome: a mid-flight failure (a Wi-Fi drop, backgrounding, a peer
    /// going out of range) reaches the delegate through `connectionFailed` instead of silently
    /// losing that message. See CODE_AUDIT_Network §5.5.
    private func send(type: GameMessageType, content: Data?) {
        // A nil encoding (encode failure) would go out as a zero-length frame, which the
        // receiver treats as the peer closing the connection. Covers every send path, not
        // only the master's ordered one. See CODE_AUDIT_19 §3.14.
        guard let content else {
            let uuid = id.uuidString
            Logger.connectionController.error("Connection: \(uuid, privacy: .public) Skipped sending a message that could not be encoded")
            return
        }
        outboundContinuation.yield(OutboundMessage(type: type, content: content))
    }

    private func sendFailed(error: any Error) async {
        // A send still in flight when the owner cancelled completes with an error too.
        guard !wasCancelledLocally else { return }
        let uuid = id.uuidString
        Logger.connectionController.error("Connection: \(uuid, privacy: .public) Send failed \(error.localizedDescription, privacy: .public)")
        teardown()
        await connectionFailed(message: error.localizedDescription, isAuthenticationFailure: Self.isAuthenticationFailure(error))
    }
}
private extension ConnectionController {
    /// Stops receiving and sending and releases the connection, without marking the cancel as
    /// the owner's. Cancelling a task waiting in `receive()`/`send()` cancels the connection (a
    /// `.cancelled` state update follows); dropping the last reference closes it otherwise.
    func teardown() {
        receiveTask?.cancel()
        receiveTask = nil
        sendTask?.cancel()
        sendTask = nil
        outboundContinuation.finish()
        connection = nil
    }

    func stateChanged(_ newState: GameConnection.State) async {
        let uuid = id.uuidString

        switch newState {
        case .ready:
            Logger.connectionController.debug("Connection: \(uuid, privacy: .public) Ready")
            await reportReady()

        case let .failed(error):
            Logger.connectionController.debug("Connection: \(uuid, privacy: .public) Failed \(error.localizedDescription, privacy: .public)")
            teardown()
            await connectionFailed(message: error.localizedDescription, isAuthenticationFailure: Self.isAuthenticationFailure(error))

        case .cancelled:
            Logger.connectionController.debug("Connection: \(uuid, privacy: .public) Cancelled")
            // Mirrors `cancel()`: without this, a receive still pending inside the receive
            // loop fires once more with a cancellation error after teardown was already
            // reported, re-entering `process()`/`connectionFailed()` for the same underlying
            // event. See CODE_AUDIT_Network §5.9.
            teardown()
            await reportCancelled()

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

    /// Only reports a fresh loss if this instance hasn't already reported a terminal outcome via
    /// `connectionFailed` — see `terminalOutcomeReported`'s own doc. An external `cancel()`
    /// (e.g. `stop()`'s own teardown, never preceded by a reported failure) still reports.
    func reportCancelled() async {
        guard !terminalOutcomeReported else { return }
        terminalOutcomeReported = true
        await lostConnection()
    }

    /// Reports `readyConnection` once, from whichever comes first: the `.ready` state update or
    /// the first received message. A late `.ready` after a terminal outcome or a local cancel
    /// reports nothing.
    func reportReady() async {
        guard !readyReported, !terminalOutcomeReported, !wasCancelledLocally else { return }
        readyReported = true
        await connectionReady()
    }

    /// Waits for each message holding only the connection: `self` is bound per message, so the
    /// `deinit` cleanup still runs when an owner drops the controller without `cancel()` (it
    /// cancels this task, which cancels the pending receive and the connection). Each message is
    /// processed before the next receive, so a slow delegate holds back the peer instead of
    /// buffering. See CODE_AUDIT_19 §3.11.
    func startReceiveLoop(on connection: GameConnection) {
        guard receiveTask == nil else { return }
        receiveTask = Task { [weak self] in
            while !Task.isCancelled {
                let received: ReceivedMessage
                do {
                    let message = try await connection.receive()
                    received = ReceivedMessage(content: message.content, type: message.metadata.framer.gameMessageType, error: nil)
                } catch {
                    received = ReceivedMessage(content: nil, type: .invalid, error: error)
                }
                guard let self else { return }
                await self.process(received)
                if received.error != nil { return }
            }
        }
    }

    /// Sends the queued messages one at a time. Holds only the connection, like the receive loop.
    func startSendLoop(on connection: GameConnection) {
        guard sendTask == nil else { return }
        let outbound = outbound
        sendTask = Task { [weak self] in
            for await message in outbound {
                do {
                    try await connection.send(message.content, metadata: NWProtocolFramer.Message(gameMessageType: message.type))
                } catch {
                    guard !Task.isCancelled else { return }
                    await self?.sendFailed(error: error)
                    return
                }
            }
        }
    }

    struct ReceivedMessage: Sendable {
        let content: Data?
        let type: GameMessageType
        let error: (any Error)?
    }

    func process(_ received: ReceivedMessage) async {
        // The receive that was pending when the owner cancelled completes with an error: the
        // teardown is already being reported through `.cancelled`.
        guard !wasCancelledLocally else { return }
        if let error = received.error {
            // A peer closing the connection (player quits, master stops a player, app
            // backgrounds) also ends the receive with an error: `GameConnection` has no
            // separate end-of-stream result. Either way the delegate hears that the connection
            // died, and the loop stops. See CODE_AUDIT_Network §5.6.
            let uuid = id.uuidString
            Logger.connectionController.error("Connection: \(uuid, privacy: .public) Error \(error.localizedDescription, privacy: .public)")
            teardown()
            await connectionFailed(message: error.localizedDescription, isAuthenticationFailure: Self.isAuthenticationFailure(error))
            return
        }
        await reportReady()
        await receivedMessage(content: received.content, type: received.type)
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

    nonisolated static func isAuthenticationFailure(_ error: any Error) -> Bool {
        guard let error = error as? NWError, case let .tls(status) = error else { return false }
        return !transientTLSStatuses.contains(status)
    }

    func receivedMessage(content: Data?, type: GameMessageType) async {
        guard type == .gameData else {
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
