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
    let networkModel: PlayerNetworkNodel
    // See CODE_AUDIT §6.1: throttles repeated bad-passcode attempts on the
    // reconnect-fallback listener (`setUpListener`/`restart`). The outbound
    // `start(model:)` join path is never throttled — this device is the one
    // dialing out there with a code the user entered, not receiving an
    // unknown attempt.
    private let connectionThrottle = ConnectionAttemptThrottle()
    private var pendingConnectionSources: [ConnectionController.ID: String] = [:]

    /// Bonjour role advertised after the outbound connection is lost. Direct
    /// players wait for the game master to reconnect, while proxy clients wait
    /// for their private proxy host.
    var fallbackServiceType: GameServiceType {
        proxy ? .proxyClient : .master
    }

    init(name: String, proxy: Bool = false, delegate: PlayerNetworkControllerDelegate? = nil) {
        self.networkModel = PlayerNetworkNodel(name: name)
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
    func toggleConnection(to model: BrowserGameModel, passcode: String) async {
        Logger.networking.debug("PlayerNetworkController: Start")
        guard networkModel.playerConnectionId == nil else {
            await stop()
            return
        }

        let endpoint = browserManager.nwEndpoint(for: model)
        let playerModel = PlayerBrowserModel(name: model.deviceName, endpoint: endpoint, interface: nil)
        networkModel.model = playerModel
        networkModel.playerConnectionId = model.id
        networkModel.passcode = passcode
        await start(model: playerModel)

        observeRemovedConnection()
    }

    func stop() async {
        Logger.playerNetworkController.debug("PlayerNetworkController: Stop")
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
        let passcode = await networkModel.passcode
        await networkModel.reset(controller: ConnectionController(id: UUID(), endpoint: model.endpoint, passcode: passcode, delegate: self))
        await networkModel.connectionController?.startConnection()
    }

    func restart(connection: NWConnection) async {
        Logger.playerNetworkController.debug("PlayerConnection: Restart connection")
        let id = UUID()
        if let source = connection.endpoint.throttleSourceKey {
            pendingConnectionSources[id] = source
        }
        await networkModel.reset(controller: ConnectionController(id: id, connection: connection, delegate: self))
        await networkModel.connectionController?.startConnection()
    }

    func startPlayerServer() async {
        guard await networkModel.listener == nil else { return }
        Logger.networking.debug("PlayerNetworkController: Create Listener")
        await setUpListener()
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
        guard await isCurrentConnection(id) else {
            Logger.playerNetworkController.debug("PlayerNetworkController: Ignore failure from replaced connection \(id.uuidString, privacy: .public)")
            return
        }
        if await networkModel.connectionState != .notReady {
            await lostConnection(for: id)
        } else {
            // A fresh reconnect attempt (state == .notReady) failing immediately
            // is a handshake/auth failure, not a previously-established
            // connection dropping — this is the passcode-guessing signal the
            // throttle tracks. Outbound `start(model:)` attempts never appear
            // here, since only `restart(connection:)` registers a pending source.
            if let source = pendingConnectionSources.removeValue(forKey: id) {
                await connectionThrottle.recordFailure(source: source)
            }
            await stop(connection: id)
        }
    }

    @MainActor
    func lostConnection(for id: ConnectionController.ID) async {
        Logger.networking.debug("PlayerNetworkController: Lost connection")
        pendingConnectionSources.removeValue(forKey: id)

        guard await markLostIfCurrent(id) else {
            Logger.playerNetworkController.debug("PlayerNetworkController: Ignore stale or duplicate loss \(id.uuidString, privacy: .public)")
            return
        }
        Logger.playerNetworkController.debug("PlayerNetworkController: Lost connection to server, start own listener")
        await startPlayerServer()
        await delegate.playerLostMaster()
    }

    @MainActor
    func readyConnection(for id: ConnectionController.ID) async {
        guard await markReadyIfCurrent(id) else {
            Logger.playerNetworkController.debug("PlayerNetworkController: Ignore ready callback from replaced connection \(id.uuidString, privacy: .public)")
            return
        }
        if let source = pendingConnectionSources.removeValue(forKey: id) {
            await connectionThrottle.recordSuccess(source: source)
        }
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
        guard let model = await networkModel.model else { return }
        Logger.playerNetworkController.debug("PlayerNetworkController: RemovedConnection \(endpoint.debugDescription, privacy: .public)")
        if model.endpoint == endpoint {
            guard let id = await networkModel.connectionController?.id else { return }
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
        if let source = connection.endpoint.throttleSourceKey, await !connectionThrottle.shouldAllow(source: source) {
            Logger.playerNetworkController.debug("PlayerNetworkController: Rejected connection attempt from throttled source")
            connection.cancel()
            return
        }
        await networkModel.reset(listener: nil)
        await networkModel.reset(isConnected: false)
        let shouldRestart = await networkModel.connectionState == .lost
        await networkModel.reset(state: .notReady)
        if shouldRestart {
            Logger.playerNetworkController.debug("PlayerNetworkController: Listener new connection")
            await restart(connection: connection)
        }
    }
}

extension Logger {
    static let playerNetworkController = Logger(subsystem: subsystem, category: "PlayerNetworkController")
}
