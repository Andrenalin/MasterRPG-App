// @copyright André Trettin

import Foundation
import Network
import os.log
import CoreRPG

final class PlayerNetworkController {
    let proxy: Bool
    private unowned let delegate: PlayerNetworkControllerDelegate?

    let browserController: BrowserController
    let networkModel: PlayerNetworkNodel

    @MainActor
    init(name: String, proxy: Bool = false, delegate: PlayerNetworkControllerDelegate? = nil) {
        self.networkModel = PlayerNetworkNodel(name: name)
        self.proxy = proxy
        self.delegate = delegate
        self.browserController = BrowserController(proxy: proxy)
        Logger.playerNetworkController.debug("PlayerNetworkController: Init")
    }

    deinit {
        Logger.playerNetworkController.debug("PlayerNetworkController: Deinit")
    }
}

extension PlayerNetworkController: PlayerNetworkControllable {
    @MainActor
    func toggleConnection(to model: BrowserDeviceModel) async {
        Logger.networking.debug("PlayerNetworkController: Start")
        guard networkModel.playerConnectionId == nil else {
            await stop()
            return
        }

        guard let playerModel = await browserController.playerConection(for: model) else { return }
        networkModel.model = playerModel
        networkModel.playerConnectionId = model.id
        await start(model: playerModel)
        
        observeRemovedConnection()
    }

    @MainActor
    func stop() async {
        Logger.playerNetworkController.debug("PlayerNetworkController: Stop")
        networkModel.connectionState = .notReady
        networkModel.connectionController?.cancel()
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
    
    func restart(nwConnection: NWConnection) async {
        Logger.playerNetworkController.debug("PlayerConnection: Restart connection")
        await networkModel.reset(controller: ConnectionController(id: UUID(), connection: nwConnection, delegate: self))
        await networkModel.connectionController?.startConnection()
    }

    func startPlayerServer() async {
        guard await networkModel.listener == nil else { return }
        Logger.networking.debug("PlayerNetworkController: Create Listener")
        await networkModel.reset(listener: await ListenerController(player: networkModel.name, delegate: self))
        await networkModel.listener?.startListening()
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
            await delegate?.playerLostMaster()
        }
    }

    func readyConnection(for id: ConnectionController.ID) async {
        await networkModel.reset(isConnected: true)
        await networkModel.reset(state: .ready)
        await delegate?.playerReady()
    }

    func received(data: Data?, for id: ConnectionController.ID) async {
        await delegate?.playerReceived(data: data)
    }
}

// MARK: - Observe BrowserController for Lost Connection

extension PlayerNetworkController {
    @MainActor
    func observeRemovedConnection() {
        guard networkModel.model != nil else { return }
        _ = withObservationTracking {
            browserController.model.removed
        } onChange: { [weak self] in
            Task {
                await self?.checkForRemoval()
            }
        }
    }

    @MainActor
    func checkForRemoval() async {
        guard networkModel.model != nil else { return }
        for result in browserController.model.removed {
            await removedConnection(for: result)
        }
        observeRemovedConnection()
    }
    
    func removedConnection(for result: NWBrowser.Result) async {
        guard let model = await networkModel.model else { return }
        Logger.playerNetworkController.debug("PlayerNetworkController: RemovedConnection \(result.endpoint.debugDescription)")
        if model.endpoint == result.endpoint {
            await lostConnection(for: UUID())
        }
    }
}

// MARK: - ListenerControllerDelegate

extension PlayerNetworkController: ListenerControllerDelegate {
    func cancelled() async {
        Logger.playerNetworkController.debug("PlayerNetworkController: Listener cancelled")
        await networkModel.reset(listener: nil)
        await stop()
    }

    func newConnection(for nwConnection: NWConnection) async {
        await networkModel.reset(listener: nil)
        await networkModel.reset(isConnected: false)
        if await networkModel.connectionState == .lost {
            Logger.playerNetworkController.debug("PlayerNetworkController: Listener new connection \(nwConnection.debugDescription)")
            await restart(nwConnection: nwConnection)
        }
        await networkModel.reset(state: .notReady)
    }
}

extension Logger {
    static let playerNetworkController = Logger(subsystem: subsystem, category: "PlayerNetworkController")
}
