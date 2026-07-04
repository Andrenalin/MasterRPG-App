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

final class PlayerNetworkController {
    let proxy: Bool
    private let delegate: PlayerNetworkControllerDelegateBox

    let browserManager: BrowserManager
    let networkModel: PlayerNetworkNodel

    @MainActor
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
    @MainActor
    func toggleConnection(to model: BrowserGameModel) async {
        Logger.networking.debug("PlayerNetworkController: Start")
        guard networkModel.playerConnectionId == nil else {
            await stop()
            return
        }

        let endpoint = browserManager.nwEndpoint(for: model)
        let playerModel = PlayerBrowserModel(name: model.deviceName, endpoint: endpoint, interface: nil)
        networkModel.model = playerModel
        networkModel.playerConnectionId = model.id
        await start(model: playerModel)

        observeRemovedConnection()
    }

    @MainActor
    func stop() async {
        Logger.playerNetworkController.debug("PlayerNetworkController: Stop")
        networkModel.observeRemovalTask?.cancel()
        networkModel.observeRemovalTask = nil
        networkModel.connectionStartTask?.cancel()
        networkModel.connectionStartTask = nil
        networkModel.connectionState = .notReady
        await networkModel.connectionController?.cancel()
        networkModel.connectionController = nil
        networkModel.playerConnectionId = nil
        networkModel.model = nil
        networkModel.isConnected = false
    }

    func request(with content: MessageMapper?) async {
        await networkModel.connectionController?.request(with: content)
    }
}

// MARK: - Player Connection Handling

private extension PlayerNetworkController {
    func start(model: PlayerBrowserModel) async {
        Logger.playerNetworkController.debug("PlayerNetworkController: Start with browser model")
        await networkModel.reset(controller: ConnectionController(id: UUID(), endpoint: model.endpoint, delegate: self))
        await networkModel.connectionController?.startConnection()
    }

    func restart(connection: NWConnection) async {
        Logger.playerNetworkController.debug("PlayerConnection: Restart connection")
        await networkModel.reset(controller: ConnectionController(id: UUID(), connection: connection, delegate: self))
        await networkModel.connectionController?.startConnection()
    }

    func startPlayerServer() async {
        guard await networkModel.listener == nil else { return }
        Logger.networking.debug("PlayerNetworkController: Create Listener")
        await MainActor.run { [weak self] in
            guard let self else { return }
            let manager = ListenerManager(name: networkModel.name, serviceType: .master)
            manager.delegate = self
            networkModel.reset(listener: manager)
            manager.startListening()
        }
    }
}

// MARK: - ConnectionControllerDelegate

extension PlayerNetworkController: ConnectionControllerDelegate {
    func failed(with error: String?, for id: ConnectionController.ID) async {
        if await networkModel.connectionState != .notReady {
            await lostConnection(for: id)
        } else {
            await stop()
        }
    }

    func lostConnection(for id: ConnectionController.ID) async {
        Logger.networking.debug("PlayerNetworkController: Lost connection")

        guard await networkModel.playerConnectionId != nil else {
            Logger.playerNetworkController.debug("PlayerNetworkController: Connection resetted by user")
            return
        }
        if await networkModel.connectionState != .lost {
            Logger.playerNetworkController.debug("PlayerNetworkController: Lost connection to server, start own listener")
            await networkModel.reset(state: .lost)
            await startPlayerServer()
            await delegate.playerLostMaster()
        }
    }

    func readyConnection(for id: ConnectionController.ID) async {
        await networkModel.reset(isConnected: true)
        await networkModel.reset(state: .ready)
        await delegate.playerReady()
    }

    func received(data: Data?, for id: ConnectionController.ID) async {
        await delegate.playerReceived(data: data)
    }
}

// MARK: - Observe BrowserManager for Lost Connection

extension PlayerNetworkController {
    @MainActor
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

    @MainActor
    private func scheduleRemovalCheck() {
        networkModel.observeRemovalTask?.cancel()
        networkModel.observeRemovalTask = Task { @MainActor [weak self] in
            await self?.checkForRemoval()
        }
    }

    @MainActor
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
            await lostConnection(for: UUID())
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

    func listenerNewConnection(_ connection: NWConnection) async {
        await networkModel.reset(listener: nil)
        await networkModel.reset(isConnected: false)
        if await networkModel.connectionState == .lost {
            Logger.playerNetworkController.debug("PlayerNetworkController: Listener new connection")
            await restart(connection: connection)
        }
        await networkModel.reset(state: .notReady)
    }
}

extension Logger {
    static let playerNetworkController = Logger(subsystem: subsystem, category: "PlayerNetworkController")
}
