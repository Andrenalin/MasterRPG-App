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

    /// Bonjour role advertised after the outbound connection is lost. Direct
    /// players wait for the game master to reconnect, while proxy clients wait
    /// for their private proxy host.
    var fallbackServiceType: GameServiceType {
        proxy ? .proxyClient : .master
    }

    init(name: String, proxy: Bool = false, delegate: PlayerNetworkControllerDelegate? = nil) {
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

        let endpoint = browserManager.nwEndpoint(for: model)
        let playerModel = PlayerBrowserModel(name: model.deviceName, endpoint: endpoint, interface: nil)
        networkModel.model = playerModel
        networkModel.playerConnectionId = model.id
        networkModel.passcode = passcode
        await start(model: playerModel)

        observeRemovedConnection()

        return await withCheckedContinuation { continuation in
            pendingJoinContinuation = continuation
        }
    }

    /// No-op if there is no attempt in flight. Guarantees `toggleConnection(to:passcode:)`
    /// never hangs waiting on a handshake outcome that a teardown elsewhere
    /// (an explicit `stop()`, a superseded attempt) already made moot.
    private func resolvePendingConnection(success: Bool) {
        pendingJoinContinuation?.resume(returning: success)
        pendingJoinContinuation = nil
    }

    func stop() async {
        Logger.playerNetworkController.debug("PlayerNetworkController: Stop")
        resolvePendingConnection(success: false)
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
        networkModel.reset(controller: ConnectionController(id: id, connection: connection, delegate: self))
        await networkModel.connectionController?.startConnection()
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
        let manager = ListenerManager(name: networkModel.name, supporterTier: networkModel.supporterTier, serviceType: fallbackServiceType, passcode: networkModel.passcode)
        manager.delegate = self
        networkModel.reset(listener: manager)
        manager.startListening()
    }
}

// MARK: - ConnectionControllerDelegate

extension PlayerNetworkController: ConnectionControllerDelegate {
    @MainActor
    func failed(with error: String?, for id: ConnectionController.ID) async {
        guard isCurrentConnection(id) else {
            Logger.playerNetworkController.debug("PlayerNetworkController: Ignore failure from replaced connection \(id.uuidString, privacy: .public)")
            return
        }
        if networkModel.connectionState != .notReady {
            await lostConnection(for: id)
        } else {
            // A fresh reconnect attempt (state == .notReady) failing immediately
            // is a handshake/auth failure, not a previously-established
            // connection dropping — this is the passcode-guessing signal the
            // throttle tracks. Outbound `start(model:)` attempts never appear
            // here, since only `restart(connection:)` registers a pending source.
            await connectionThrottle.resolve(id: id, succeeded: false)
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
    func observeRemovedConnection() {
        guard networkModel.model != nil else { return }
        _ = withObservationTracking {
            browserManager.removed
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleRemovalCheck()
            }
        }
    }

    private func scheduleRemovalCheck() {
        networkModel.observeRemovalTask?.cancel()
        networkModel.observeRemovalTask = Task { @MainActor [weak self] in
            await self?.checkForRemoval()
        }
    }

    func checkForRemoval() async {
        guard networkModel.model != nil else { return }
        for game in browserManager.removed {
            let endpoint = browserManager.nwEndpoint(for: game)
            await removedConnection(endpoint: endpoint)
        }
        observeRemovedConnection()
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
    func listenerCancelled() async {
        Logger.playerNetworkController.debug("PlayerNetworkController: Listener cancelled")
        await networkModel.reset(listener: nil)
        await stop()
    }

    @MainActor
    func listenerNewConnection(_ connection: NWConnection) async {
        guard await connectionThrottle.shouldAllow(endpoint: connection.endpoint) else {
            Logger.playerNetworkController.debug("PlayerNetworkController: Rejected connection attempt from throttled source")
            connection.cancel()
            return
        }
        networkModel.reset(listener: nil)
        networkModel.reset(isConnected: false)
        let shouldRestart = networkModel.connectionState == .lost
        networkModel.reset(state: .notReady)
        if shouldRestart {
            Logger.playerNetworkController.debug("PlayerNetworkController: Listener new connection")
            await restart(connection: connection)
        } else {
            // The listener that accepted this connection was just dropped
            // above (`reset(listener: nil)`), and nothing else takes
            // ownership of `connection` in this branch. Without an explicit
            // cancel, the peer that just dialed in gets no response and must
            // wait out its own OS-level connect timeout before it learns the
            // attempt failed. See CODE_AUDIT §5.1.
            Logger.playerNetworkController.debug("PlayerNetworkController: Dropping connection attempt outside a reconnect")
            connection.cancel()
        }
    }
}

extension Logger {
    static let playerNetworkController = Logger(subsystem: subsystem, category: "PlayerNetworkController")
}
