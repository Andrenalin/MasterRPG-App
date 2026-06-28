// @copyright André Trettin

import CoreRPG
import Foundation
import os.log
import SwiftUI

final class NetworkProxyController: Sendable {
    let model: NetworkProxyControllerModel

    @MainActor static let defaultMasterStoreBuilder: (String, MasterNetworkControllerDelegate) -> any MasterNetworkControllable = { name, delegate in
        MasterNetworkController(name: name, delegate: delegate, listnerBuilder: MasterNetworkController.gameListnerBuilder())
    }

    @MainActor static let defaultPlayerStoreBuilder: (String, PlayerNetworkControllerDelegate) -> any PlayerNetworkControllable = { name, delegate in
        PlayerNetworkController(name: name, proxy: true, delegate: delegate)
    }

    @MainActor
    init(name: String = "", masterBuilder: @escaping (String, MasterNetworkControllerDelegate) -> any MasterNetworkControllable = NetworkProxyController.defaultMasterStoreBuilder, playerBuilder: @escaping (String, PlayerNetworkControllerDelegate) -> any PlayerNetworkControllable = NetworkProxyController.defaultPlayerStoreBuilder) {
        self.model = NetworkProxyControllerModel(name: name)
        let masterNetworkController = masterBuilder(name, self)
        let playerNetworkController = playerBuilder(name, self)
        model.setControllers(master: masterNetworkController, player: playerNetworkController)
        Logger.networking.debug("NetworkProxy: Init \(name)")
    }

    deinit {
        let name = model.name
        Logger.networking.debug("NetworkProxy: deinit \(name)")
    }
}

// MARK: - Control

extension NetworkProxyController {
    @MainActor
    func startProxyServer() {
        let name = model.name
        Logger.networking.debug("NetworkProxy: start proxy game \(name)")
        model.masterNetworkController?.startProxyStreaming()
    }

    @MainActor
    func startPlayerGame(to model: BrowserGameModel?) async -> Bool {
        let name = self.model.name
        Logger.networking.debug("NetworkProxy: start player game \(name)")
        if let model {
            await self.model.playerNetworkController?.toggleConnection(to: model)
            return true
        }
        return false
    }

    @MainActor
    func stopGame() async {
        let name = model.name
        Logger.networking.debug("NetworkProxy: stop game \(name)")
        if model.masterNetworkController?.networkModel.isStreaming ?? false {
            model.masterNetworkController?.stopStreaming()
            await model.playerNetworkController?.stop()
        } else {
            await model.playerNetworkController?.stop()
        }
    }
}

// MARK: - Master

extension NetworkProxyController {
    func sendPlayer(_ data: GameNetworkModel, to connectionId: ConnectionController.ID) async {
        // send only to network with id
        await model.masterNetworkController?.sendResponse(data: data, id: connectionId)
    }

    func sendPlayer(data: GameNetworkModel, initial _: Bool = false) async {
        await model.masterNetworkController?.sendResponse(data: data)
    }
}

// MARK: - MasterNetworkControllerDelegate

extension NetworkProxyController: MasterNetworkControllerDelegate {
    func masterLostPlayer(with _: ConnectionController.ID) async {
        // inform master, that a player connection got disconnected, UI?
    }

    func masterReady(for connectionId: ConnectionController.ID) async {
        await model.masterDelegate?.readyProxy(for: connectionId)
    }

    func masterReceived(data: Data?, for connectionId: ConnectionController.ID, fileJournal: Bool) async {
        guard let gameData = GameNetworkModel.decodeData(of: data) else {
            Logger.networking.debug("NetworkProxy: Master Received invalid game data from \(connectionId)")
            return
        }
        // don't resend to all player in proxy mode (endless loop)
        await model.masterDelegate?.receivedServerProxy(gameData)
    }
}

// MARK: - Player

extension NetworkProxyController {
    func sendMaster(data: GameNetworkModel) async {
        await model.playerNetworkController?.request(with: data)
    }
}

// MARK: - PlayerStoreDelegate

extension NetworkProxyController: PlayerNetworkControllerDelegate {
    func playerLostMaster() {
        Task { @concurrent in
            await model.playerDelegate?.lostProxyConnection()
        }
    }

    func playerReady() {
        Task { @concurrent in
            await model.playerDelegate?.readyProxy()
        }
    }

    func playerReceived(data: Data?) {
        guard let gameData = GameNetworkModel.decodeData(of: data) else {
            Logger.networking.debug("NetworkProxy: Player received invalid game data")
            return
        }

        Task { @concurrent in
            await model.playerDelegate?.receivedProxy(gameData)
        }
    }
}

// TODO: check

extension NetworkProxyController {
    func isStreaming() async -> Bool {
        await model.masterNetworkController?.networkModel.isStreaming ?? false
    }

    // TODO: better in start Game with name?
    func resetName(name: String) {
        Task { @MainActor in
            model.masterNetworkController?.networkModel.name = name
            model.playerNetworkController?.networkModel.name = name
        }
    }
}
