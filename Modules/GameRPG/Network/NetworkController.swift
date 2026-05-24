// @copyright André Trettin

import CoreRPG
import Combine
import Foundation
import os.log
import SwiftUI
import GroupActivities

final class NetworkController: Sendable {
    let model: NetworkControllerModel
    
    @MainActor
    let sharePlayStore: RPGSharePlayController

    @MainActor static let defaultMasterStoreBuilder: (String, MasterNetworkControllerDelegate) -> any MasterNetworkControllable = { name, delegate in
        MasterNetworkController(name: name, delegate: delegate, listnerBuilder: MasterNetworkController.gameListnerBuilder())
    }

    @MainActor static let defaultPlayerStoreBuilder: (String, PlayerNetworkControllerDelegate) -> any PlayerNetworkControllable = { name, delegate in
        PlayerNetworkController(name: name, delegate: delegate)
    }

    @MainActor
    init(name: String = "", masterBuilder: @escaping (String, MasterNetworkControllerDelegate) -> any MasterNetworkControllable = NetworkController.defaultMasterStoreBuilder, playerBuilder: @escaping (String, PlayerNetworkControllerDelegate) -> any PlayerNetworkControllable = NetworkController.defaultPlayerStoreBuilder) {

        sharePlayStore = RPGSharePlay.store
        self.model = NetworkControllerModel(name: name)
        let masterNetworkController = masterBuilder(name, self)
        let playerNetworkController = playerBuilder(name, self)
        model.setControllers(master: masterNetworkController, player: playerNetworkController)

        Logger.networking.debug("NetworkController: Init \(name, privacy: .public)")
    }

    deinit {
        let name = model.name
        Logger.networking.debug("NetworkController: deinit \(name, privacy: .public)")
    }

    @MainActor
    func setup(gameModel: GameModel) {
        guard !model.isSetup else { return }
        sharePlayStore.setup(gameModel: gameModel)
        sharePlayStore.delegate = self
        model.didSetup()
    }

    func setupLocal() async {
        await model.setLocalPlayers(to: true)
    }
}

// MARK: - Control

extension NetworkController {
    @MainActor
    func startMasterGame(game: GameConfigModel, titleImage: AKImage?) async {
        let name = model.name
        Logger.networking.debug("NetworkController: start master game \(name, privacy: .public)")
        model.masterStore?.startStreaming()

        if sharePlayStore.canActivateSharePlay {
            sharePlayStore.startSharing(with: game.master.adventureTitle, image: titleImage)
            sharePlayStore.joinGame()
        }
    }

    @MainActor
    func startPlayerGame(to model: BrowserDeviceModel?) async -> Bool {
        let name = self.model.name
        Logger.networking.debug("NetworkController: start player game \(name, privacy: .public)")
        if let model {
            await self.model.playerStore?.toggleConnection(to: model)
            return true
        }
        if sharePlayStore.canActivateSharePlay {
            sharePlayStore.joinGame()
            return true
        }
        return false
    }

    @MainActor
    func stopGame() async {
        let name = model.name
        Logger.networking.debug("NetworkController: stop game \(name, privacy: .public)")
        if await isStreaming()  {
            model.masterStore?.stopStreaming()
            await model.playerStore?.stop()
            sharePlayStore.reset()
        } else {
            await model.playerStore?.stop()
            sharePlayStore.groupSession?.leave()
        }
        model.setLocalPlayers(to: false)
    }
}

// MARK: - Master

extension NetworkController {
    @MainActor
    func sendPlayer(_ data: GameNetworkModel, to connectionId: ConnectionController.ID) async {
        // send only to network with id
        await model.masterStore?.sendResponse(data: data, id: connectionId)
        if model.hasLocalPlayer {
            await model.playerDelegate?.received(data)
        }
    }

    @MainActor
    func sendPlayer(data: GameNetworkModel, fileJournal: Bool) async {
        await model.masterStore?.sendResponse(data: data)
        sharePlayStore.sendData(data, fileJournal: fileJournal)
        if model.hasLocalPlayer {
            await model.playerDelegate?.received(data)
        }
    }
}

// MARK: - MasterNetworkControllerDelegate

extension NetworkController: MasterNetworkControllerDelegate {
    func masterLostPlayer(with connectionId: ConnectionController.ID) async {
        await model.masterDelegate?.lostPlayer(for: connectionId)
    }

    func masterReady(for connectionId: ConnectionController.ID) async {
        await model.masterDelegate?.ready(for: connectionId)
    }

    func masterReceived(data: Data?, for connectionId: ConnectionController.ID, fileJournal: Bool) async {
        guard let gameData = GameNetworkModel.decodeData(of: data) else {
            Logger.networking.debug("NetworkController: Master Received invalid game data from \(connectionId)")
            return
        }
        // send all other player the same data to simulate SharePlay
        await model.masterStore?.sendResponse(data: gameData, except: connectionId)
        await MainActor.run { sharePlayStore.sendData(gameData, fileJournal: fileJournal) }
        // state
        await model.masterDelegate?.received(gameData, connectionId: connectionId)
    }
}

// MARK: - Player

extension NetworkController {
    @MainActor
    func sendMaster(data: GameNetworkModel, fileJournal: Bool) async {
        guard !model.hasLocalPlayer else { return }
        await model.playerStore?.request(with: data)
        sharePlayStore.sendData(data, fileJournal: fileJournal)
    }
}

// MARK: - PlayerStoreDelegate

extension NetworkController: PlayerNetworkControllerDelegate {
    func playerLostMaster() async {
        await model.playerDelegate?.lostConnection()
    }

    func playerReady() async {
        await model.playerDelegate?.ready()
    }

    func playerReceived(data: Data?) async {
        guard let gameData = GameNetworkModel.decodeData(of: data) else {
            Logger.networking.debug("NetworkController: Player received invalid game data")
            return
        }
        await model.playerDelegate?.received(gameData)
    }
}

// MARK: - SharePlay

extension NetworkController: SharePlayControllerDelegate {
    func handleInitial(_ model: GameNetworkModel) {
        Task { @concurrent in
            await self.model.playerDelegate?.received(model)
        }
    }

    func handleUpdate(_ model: GameNetworkModel, id: UUID) {
        Task { @concurrent in
            await self.model.playerDelegate?.received(model)
            await self.model.masterDelegate?.received(model, connectionId: id)

            if await self.model.hasLocalPlayer {
                await self.model.masterStore?.sendResponse(data: model)
            }
        }
    }

    func handleFileUpdate(_ model: GameNetworkModel) {
        Task { @concurrent in
            await self.model.playerDelegate?.receivedFile(model)
            await self.model.masterDelegate?.receivedFile(model)

            if await self.model.hasLocalPlayer {
                await self.model.masterStore?.sendResponse(data: model)
            }
        }
    }

    func sharePlayLostPlayer(id: UUID) {
        Task { @concurrent in
            await model.masterDelegate?.lostPlayer(for: id)
        }
    }
}

// TODO: check

extension NetworkController {
    func isStreaming() async -> Bool {
        await model.masterStore?.networkModel.isStreaming ?? false
    }

    // TODO: better in start Game with name?
    func resetName(name: String) {
        Task { @MainActor in
            model.masterStore?.networkModel.name = name
            model.playerStore?.networkModel.name = name
        }
    }
}
