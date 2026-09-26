// @copyright André Trettin

import Foundation
import Network
import os.log
import CoreRPG

actor PlayerNetworkControllerDelegateBox {
    private weak var delegate: (any PlayerNetworkControllerDelegate)?

    init(_ delegate: (any PlayerNetworkControllerDelegate)?) {
        self.delegate = delegate
    }

    func playerLostMaster() async {
        await delegate?.playerLostMaster()
    }

    func playerReceived(data: Data?) async {
        await delegate?.playerReceived(data: data)
    }

    func playerReady() async {
        await delegate?.playerReady()
    }
}

@MainActor
final class PlayerNetworkController: Sendable {
    let proxy: Bool
    private let delegate: PlayerNetworkControllerDelegateBox

    let browserManager: BrowserManager
    let networkModel: PlayerNetworkModel
    // See CODE_AUDIT §6.1: throttles repeated bad-passcode attempts on the
    // reconnect-fallback listener (`setUpListener`/`restart`). The outbound
    // `start(model:)` join path is never throttled — this device is the one
    // dialing out there with a code the user entered, not receiving an
    // unknown attempt.
    // See CODE_AUDIT §9.7 for why this is the shared `ConnectionThrottleTracker`
    // rather than a hand-rolled throttle + pending-sources dictionary here.
    private let connectionThrottle = ConnectionThrottleTracker()

    /// Resolved by `readyConnection(for:)` (true) or by the first-attempt
    /// branch of `failed(with:for:)` (false), and drained defensively by
    /// `stop()` for every other teardown path — so `toggleConnection(to:passcode:)`
    /// reports the *actual* handshake outcome instead of returning as soon as
    /// the attempt is merely dialed. Without this, a wrong join code (e.g. a
    /// stale `lastUsedMasterJoinCode`) let the caller believe the game had
    /// already started before the TLS/passcode handshake even completed,
    /// navigating into the game screen instead of back to the code-entry
    /// sheet. See CODE_AUDIT_Network.
    private var pendingJoinContinuation: CheckedContinuation<Bool, Never>?

    /// Identifies the in-flight `toggleConnection(to:passcode:)` attempt, if
    /// any. Set *synchronously* before the first `await` in `toggleConnection`
    /// so a second call arriving while the first is still mid-setup (e.g. a
    /// double-tap on "Join", or a caller racing `toggleConnection` against
    /// itself) is detectable even though `pendingJoinContinuation` hasn't
    /// been parked yet. `stop()` clears this, so the first call can tell —
    /// once it resumes past its own `await`s — that its attempt was
    /// superseded and must resolve to `false` immediately instead of parking
    /// a continuation nothing will ever resume. See CODE_AUDIT_13 §3.1.
    private var joinAttemptToken: UUID?
    /// The outcome of an attempt that resolved while `toggleConnection` was still suspended in
    /// `start(model:)`, so no continuation was parked to receive it. See CODE_AUDIT_16 §3.7.
    private var unclaimedJoinOutcome: (token: UUID, success: Bool)?

    /// Forces a stalled join to resolve after `joinTimeout` instead of
    /// hanging forever, covering `NWConnection.State.waiting` (Local Network
    /// permission not yet granted, an unreachable/firewalled peer, no usable
    /// path) — a state `ConnectionController.stateChanged(_:)` never reports
    /// to this delegate, since it isn't a terminal `.failed`/`.cancelled`.
    /// Cancelled by `resolvePendingConnection(success:)` on every real
    /// resolution path. See CODE_AUDIT_13 §3.1.
    private var joinTimeoutTask: Task<Void, Never>?
    private static let joinTimeout: Duration = .seconds(12)

    /// True from the moment the master connection is lost until a reconnect authenticates (or
    /// the controller stops): the fallback listener must survive failed connection attempts
    /// while this is set. See CODE_AUDIT_Join §5.1.
    private var isAwaitingReconnect = false
    private var listenerRetryTask: Task<Void, Never>?
    private var listenerRetryAttempt = 0
    private var reconnectDeadlineTask: Task<Void, Never>?
    /// How long a reconnect connection may stay unauthenticated before it is dropped, so a
    /// stalled peer cannot keep the real master out.
    static let reconnectHandshakeDeadline: Duration = .seconds(15)
    static let listenerRetryDelays: [Duration] = [.seconds(1), .seconds(2), .seconds(4), .seconds(8), .seconds(15), .seconds(30)]

    /// Arguments: name, supporter tier, service type, passcode, session id, delegate.
    private let makeListener: @MainActor (String, SupporterTier, GameServiceType, String, String?, any ListenerManagerDelegate) -> any ListenerManaging

    /// Bonjour role advertised after the outbound connection is lost. Direct
    /// players wait for the game master to reconnect, while proxy clients wait
    /// for their private proxy host.
    var fallbackServiceType: GameServiceType {
        proxy ? .proxyClient : .master
    }

    init(
        name: String,
        proxy: Bool = false,
        delegate: PlayerNetworkControllerDelegate? = nil,
        listenerBuilder: (@MainActor (String, SupporterTier, GameServiceType, String, String?, any ListenerManagerDelegate) -> any ListenerManaging)? = nil
    ) {
        self.makeListener = listenerBuilder ?? { name, supporterTier, serviceType, passcode, sessionId, delegate in
            let manager = ListenerManager(name: name, supporterTier: supporterTier, serviceType: serviceType, passcode: passcode, sessionId: sessionId)
            manager.delegate = delegate
            return manager
        }
        self.networkModel = PlayerNetworkModel(name: name)
        self.proxy = proxy
        self.delegate = PlayerNetworkControllerDelegateBox(delegate)
        self.browserManager = BrowserManager(serviceType: proxy ? .proxyServer : .player)
        Logger.playerNetworkController.debug("PlayerNetworkController: Init")
    }

    deinit {
        Logger.playerNetworkController.debug("PlayerNetworkController: Deinit")
    }
}

extension PlayerNetworkController: PlayerNetworkControllable {
    func toggleConnection(to model: BrowserGameModel, passcode: String) async -> Bool {
        Logger.networking.debug("PlayerNetworkController: Start")
        guard networkModel.playerConnectionId == nil else {
            await stop()
            return false
        }

        // Recorded synchronously, before the first `await` below, so a
        // second call that arrives while this one is still mid-setup sees
        // `playerConnectionId` already set (via the guard above), tears this
        // attempt down via `stop()`, and clears this token — letting this
        // call detect the supersession once it resumes and bail out instead
        // of parking a continuation `stop()` already made unresolvable.
        let token = UUID()
        joinAttemptToken = token

        let endpoint = browserManager.nwEndpoint(for: model)
        let playerModel = PlayerBrowserModel(name: model.deviceName, endpoint: endpoint, interface: nil)
        networkModel.model = playerModel
        networkModel.playerConnectionId = model.id
        networkModel.passcode = passcode
        networkModel.sessionId = model.sessionId
        networkModel.joinFailure = nil
        await start(model: playerModel)

        guard joinAttemptToken == token else {
            if let outcome = unclaimedJoinOutcome, outcome.token == token {
                // `.ready` (or a failure) landed while `start` was suspended: report it
                // instead of calling a live connection "superseded".
                unclaimedJoinOutcome = nil
                if outcome.success { observeRemovedConnection() }
                return outcome.success
            }
            Logger.playerNetworkController.debug("PlayerNetworkController: Join attempt superseded before continuation was parked")
            return false
        }

        observeRemovedConnection()

        joinTimeoutTask?.cancel()
        joinTimeoutTask = Task { @MainActor [weak self, timeout = Self.joinTimeout] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled, let self, self.joinAttemptToken == token else { return }
            // Covers `NWConnection.State.waiting` (Local Network permission
            // not yet granted, unreachable/firewalled peer, no usable
            // path), which never reaches `.failed`/`.cancelled` and so
            // never calls back into this delegate on its own.
            Logger.playerNetworkController.debug("PlayerNetworkController: Join timed out waiting for a terminal connection state")
            self.networkModel.joinFailure = .timedOut
            await self.stop()
        }

        // A cancelled caller (dismissed join sheet) abandons the attempt instead of staying
        // parked until the join timeout. `stop()` resolves the continuation.
        // See CODE_AUDIT_18 §3.12.
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                pendingJoinContinuation = continuation
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, self.joinAttemptToken == token else { return }
                await self.stop()
            }
        }
    }

    /// No-op if there is no attempt in flight. Guarantees `toggleConnection(to:passcode:)`
    /// never hangs waiting on a handshake outcome that a teardown elsewhere
    /// (an explicit `stop()`, a superseded attempt) already made moot.
    private func resolvePendingConnection(success: Bool) {
        if pendingJoinContinuation == nil, let token = joinAttemptToken {
            unclaimedJoinOutcome = (token, success)
        }
        joinAttemptToken = nil
        joinTimeoutTask?.cancel()
        joinTimeoutTask = nil
        pendingJoinContinuation?.resume(returning: success)
        pendingJoinContinuation = nil
    }

    func stop() async {
        Logger.playerNetworkController.debug("PlayerNetworkController: Stop")
        resolvePendingConnection(success: false)
        isAwaitingReconnect = false
        listenerRetryTask?.cancel()
        listenerRetryTask = nil
        listenerRetryAttempt = 0
        reconnectDeadlineTask?.cancel()
        reconnectDeadlineTask = nil
        let connectionController = networkModel.connectionController
        networkModel.observeRemovalTask?.cancel()
        networkModel.observeRemovalTask = nil
        networkModel.connectionStartTask?.cancel()
        networkModel.connectionStartTask = nil
        networkModel.connectionState = .notReady
        networkModel.connectionController = nil
        networkModel.playerConnectionId = nil
        networkModel.model = nil
        networkModel.isConnected = false
        // The join code is only needed while a session is being set up or recovered.
        networkModel.passcode = ""
        networkModel.sessionId = nil
        // The fallback listener (`startPlayerServer()`) is owned only by this
        // controller, not by `ConnectionController`, and is never torn down
        // by any of its own delegate callbacks when the *controller* — not
        // the listener — decides to stop. Without this, a listener started
        // while `.lost` outlives `stop()` (leaking the Bonjour advertisement
        // and open socket), and `startPlayerServer()`'s `listener == nil`
        // guard then silently disables the fallback-reconnect recovery for
        // every future lost-master event in this app run. See
        // CODE_AUDIT_Reconnect §5.1.
        let listener = networkModel.listener
        networkModel.reset(listener: nil)
        listener?.stopListening()
        await connectionController?.cancel()
    }

    func request(with content: MessageMapper?) async {
        await networkModel.connectionController?.request(with: content)
    }
}

// MARK: - Player Connection Handling

private extension PlayerNetworkController {
    func start(model: PlayerBrowserModel) async {
        Logger.playerNetworkController.debug("PlayerNetworkController: Start with browser model")
        let passcode = networkModel.passcode
        networkModel.reset(controller: ConnectionController(id: UUID(), endpoint: model.endpoint, passcode: passcode, delegate: self))
        await networkModel.connectionController?.startConnection()
    }

    func restart(connection: NWConnection) async {
        Logger.playerNetworkController.debug("PlayerConnection: Restart connection")
        let id = UUID()
        await connectionThrottle.register(id: id, endpoint: connection.endpoint)
        // The replaced controller's receive loop holds it alive, so it must be cancelled
        // explicitly or its socket lingers until TCP fails. See CODE_AUDIT_Join §3.1.
        let replaced = networkModel.connectionController
        networkModel.reset(controller: ConnectionController(id: id, connection: connection, delegate: self))
        await replaced?.cancel()
        await networkModel.connectionController?.startConnection()
        enforceReconnectDeadline(for: id)
    }

    /// Drops a reconnect attempt that has not authenticated in time; the resulting cancellation
    /// returns the player to `.lost` with the listener still advertising.
    func enforceReconnectDeadline(for id: ConnectionController.ID) {
        reconnectDeadlineTask?.cancel()
        reconnectDeadlineTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.reconnectHandshakeDeadline)
            guard !Task.isCancelled, let self, self.isCurrentConnection(id), self.networkModel.connectionState == .notReady else { return }
            Logger.playerNetworkController.debug("PlayerNetworkController: Reconnect handshake deadline expired")
            await self.networkModel.connectionController?.cancel()
        }
    }

    /// A reconnect attempt failed before authenticating: go back to waiting for the master with
    /// the fallback listener still up (recreating it if it was lost meanwhile), instead of ending
    /// the session for one bad connection. See CODE_AUDIT_Join §5.1.
    func returnToWaiting() async {
        reconnectDeadlineTask?.cancel()
        reconnectDeadlineTask = nil
        networkModel.reset(isConnected: false)
        networkModel.reset(state: .lost)
        if networkModel.listener == nil {
            await startPlayerServer()
        }
    }

    func startPlayerServer() async {
        guard networkModel.listener == nil else { return }
        Logger.networking.debug("PlayerNetworkController: Create Listener")
        setUpListener()
    }

    private func setUpListener() {
        // Reuses the passcode this session's outbound connection was made
        // with — the peer on the other end already knows it, so no new code
        // entry is needed to re-admit them if they reconnect.
        let manager = makeListener(networkModel.name, networkModel.supporterTier, fallbackServiceType, networkModel.passcode, networkModel.sessionId, self)
        networkModel.reset(listener: manager)
        manager.startListening()
    }
}

// MARK: - ConnectionControllerDelegate

extension PlayerNetworkController: ConnectionControllerDelegate {
    @MainActor
    func failed(with error: String?, isAuthenticationFailure: Bool = true, for id: ConnectionController.ID) async {
        guard isCurrentConnection(id) else {
            Logger.playerNetworkController.debug("PlayerNetworkController: Ignore failure from replaced connection \(id.uuidString, privacy: .public)")
            return
        }
        if networkModel.connectionState != .notReady {
            await lostConnection(for: id)
        } else {
            // A fresh reconnect attempt (state == .notReady) failing immediately
            // covers both a handshake/auth rejection (the passcode-guessing
            // signal the throttle tracks) and an ordinary transient failure
            // (Wi-Fi drop, timeout, unreachable peer — exactly what a
            // legitimate automatic reconnect retry can hit). Only the former
            // is evidence of a bad-passcode guess; counting the latter toward
            // the lockout would let a flaky network eventually throttle a
            // real peer out of reconnecting to itself. Outbound `start(model:)`
            // attempts never appear here, since only `restart(connection:)`
            // registers a pending source. See CODE_AUDIT_Reconnect §6.1.
            if isAuthenticationFailure {
                await connectionThrottle.resolve(id: id, succeeded: false)
            } else {
                await connectionThrottle.clear(id: id)
            }
            if isAwaitingReconnect {
                await returnToWaiting()
                return
            }
            networkModel.joinFailure = isAuthenticationFailure ? .badCode : .unreachable
            // Also covers an outbound `start(model:)` attempt made with a bad
            // join code: the TLS/passcode handshake fails right here, so the
            // caller waiting in `toggleConnection(to:passcode:)` must be told
            // it did not connect, not left assuming the earlier dial succeeded.
            resolvePendingConnection(success: false)
            await stop(connection: id)
        }
    }

    @MainActor
    func lostConnection(for id: ConnectionController.ID) async {
        Logger.networking.debug("PlayerNetworkController: Lost connection")
        await connectionThrottle.clear(id: id)

        if isCurrentConnection(id), networkModel.connectionState == .notReady {
            if isAwaitingReconnect {
                await returnToWaiting()
                return
            }
            networkModel.joinFailure = .unreachable
            // The connection was torn down (e.g. the underlying `NWConnection`
            // reporting `.cancelled` for a rejected handshake instead of
            // `.failed`) before ever reaching `.ready`. This is an initial-join
            // failure, not a previously-established session dropping, so it
            // must resolve the pending `toggleConnection(to:passcode:)` call
            // the same way `failed(with:for:)` does — otherwise that call
            // hangs forever (nothing else ever resolves it), leaving the
            // caller stuck believing the join is still in flight instead of
            // prompting for a fresh code. The "lost master, become a fallback
            // listener" recovery below assumes a session that never existed.
            resolvePendingConnection(success: false)
            await stop(connection: id)
            return
        }

        guard markLostIfCurrent(id) else {
            Logger.playerNetworkController.debug("PlayerNetworkController: Ignore stale or duplicate loss \(id.uuidString, privacy: .public)")
            return
        }
        Logger.playerNetworkController.debug("PlayerNetworkController: Lost connection to server, start own listener")
        isAwaitingReconnect = true
        listenerRetryAttempt = 0
        await startPlayerServer()
        await delegate.playerLostMaster()
    }

    @MainActor
    func readyConnection(for id: ConnectionController.ID) async {
        guard markReadyIfCurrent(id) else {
            Logger.playerNetworkController.debug("PlayerNetworkController: Ignore ready callback from replaced connection \(id.uuidString, privacy: .public)")
            return
        }
        await connectionThrottle.resolve(id: id, succeeded: true)
        // The master authenticated: the fallback listener has done its job. It is retired here,
        // not when a connection first arrives. See CODE_AUDIT_Join §5.1.
        isAwaitingReconnect = false
        listenerRetryTask?.cancel()
        listenerRetryTask = nil
        reconnectDeadlineTask?.cancel()
        reconnectDeadlineTask = nil
        let fallbackListener = networkModel.listener
        networkModel.reset(listener: nil)
        fallbackListener?.stopListening()
        resolvePendingConnection(success: true)
        await delegate.playerReady()
    }

    func received(data: Data?, for id: ConnectionController.ID) async {
        guard await isCurrentConnection(id) else {
            Logger.playerNetworkController.debug("PlayerNetworkController: Ignore data from replaced connection \(id.uuidString, privacy: .public)")
            return
        }
        await delegate.playerReceived(data: data)
    }
}

private extension PlayerNetworkController {
    func isCurrentConnection(_ id: ConnectionController.ID) -> Bool {
        networkModel.connectionController?.id == id
    }

    func markLostIfCurrent(_ id: ConnectionController.ID) -> Bool {
        guard isCurrentConnection(id),
              networkModel.playerConnectionId != nil,
              networkModel.connectionState != .lost else { return false }
        networkModel.reset(state: .lost)
        return true
    }

    func markReadyIfCurrent(_ id: ConnectionController.ID) -> Bool {
        guard isCurrentConnection(id), networkModel.connectionState != .lost else { return false }
        networkModel.reset(isConnected: true)
        networkModel.reset(state: .ready)
        return true
    }

    func stop(connection id: ConnectionController.ID) async {
        guard isCurrentConnection(id) else { return }
        await stop()
    }
}

// MARK: - Observe BrowserManager for Lost Connection

extension PlayerNetworkController {
    /// One stored `Observations` loop instead of re-arming `withObservationTracking` per
    /// change. It delivers every change for the task's lifetime, so a removal landing while
    /// an earlier batch is still being torn down is not missed. See CODE_AUDIT_18 §3.21.
    func observeRemovedConnection() {
        guard networkModel.model != nil else { return }
        let browser = browserManager
        networkModel.observeRemovalTask?.cancel()
        networkModel.observeRemovalTask = Task { @MainActor [weak self] in
            for await removed in Observations({ browser.removed }) {
                guard let self, !Task.isCancelled else { return }
                // `takeRemoved()` below empties the list, which is itself a change.
                guard !removed.isEmpty else { continue }
                await self.checkForRemoval()
            }
        }
    }

    func checkForRemoval() async {
        guard networkModel.model != nil else { return }
        // Re-arm `withObservationTracking` before processing the current
        // batch, not after. `onChange` fires once and must be re-registered
        // before the next mutation to be seen at all; the async teardown
        // below (`removedConnection` → `lostConnection` → several actor hops
        // and `stop()`'s own connection teardown) can take long enough that a
        // second Bonjour-removal change lands while still in flight — arming
        // late meant that change was missed until some later, unrelated
        // mutation happened to re-trigger observation. A second
        // `checkForRemoval()` scheduled by that re-registration racing this
        // one's own loop is safe: `lostConnection(for:)` is already
        // idempotent via `markLostIfCurrent`. See CODE_AUDIT_Reconnect §3.5.
        let removedGames = browserManager.takeRemoved()
        for game in removedGames {
            let endpoint = browserManager.nwEndpoint(for: game)
            await removedConnection(endpoint: endpoint)
        }
    }

    func removedConnection(endpoint: NWEndpoint) async {
        guard let model = networkModel.model else { return }
        Logger.playerNetworkController.debug("PlayerNetworkController: RemovedConnection \(endpoint.debugDescription, privacy: .private)")
        if model.endpoint == endpoint {
            guard let id = networkModel.connectionController?.id else { return }
            await lostConnection(for: id)
        }
    }
}

// MARK: - ListenerManagerDelegate

extension PlayerNetworkController: ListenerManagerDelegate {
    @MainActor
    func listenerReady() async {}

    /// The fallback listener failed. While the player is still waiting for its master it is
    /// recreated after a pause; only when that keeps failing (or there is nothing to wait for)
    /// does the controller stop. See CODE_AUDIT_Join §5.3.
    @MainActor
    func listenerCancelled() async {
        Logger.playerNetworkController.debug("PlayerNetworkController: Listener cancelled")
        networkModel.reset(listener: nil)
        guard isAwaitingReconnect, networkModel.playerConnectionId != nil,
              listenerRetryAttempt < Self.listenerRetryDelays.count + 3 else {
            await stop()
            return
        }
        let delay = Self.listenerRetryDelays[min(listenerRetryAttempt, Self.listenerRetryDelays.count - 1)]
        listenerRetryAttempt += 1
        listenerRetryTask?.cancel()
        listenerRetryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, self.isAwaitingReconnect, self.networkModel.listener == nil else { return }
            await self.startPlayerServer()
        }
    }

    @MainActor
    func listenerNewConnection(_ connection: NWConnection) async {
        guard await connectionThrottle.shouldAllow(endpoint: connection.endpoint) else {
            Logger.playerNetworkController.debug("PlayerNetworkController: Rejected connection attempt from throttled source")
            connection.cancel()
            return
        }
        // Only a lost player takes a connection, and only one at a time. The listener stays up
        // either way: it is retired when a connection authenticates, so one unauthenticated or
        // foreign connection can no longer end the reconnect. See CODE_AUDIT_Join §5.1.
        guard networkModel.connectionState == .lost else {
            Logger.playerNetworkController.debug("PlayerNetworkController: Dropping connection attempt outside a reconnect")
            connection.cancel()
            return
        }
        Logger.playerNetworkController.debug("PlayerNetworkController: Listener new connection")
        networkModel.reset(isConnected: false)
        networkModel.reset(state: .notReady)
        await restart(connection: connection)
    }
}

extension Logger {
    static let playerNetworkController = Logger(subsystem: subsystem, category: "PlayerNetworkController")
}
