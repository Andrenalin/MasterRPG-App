// @copyright André Trettin

import  CoreRPG
import Foundation
import os.log

@MainActor @Observable
final class MasterControllerModel: Sendable {
    var messageCounter: Int = 0
    var seenCounter: Int = 0
    var connectIDPlayers: [ConnectionController.ID: UUID] = [:]
    var asProxy = false
    
    func increaseMessageCounter() {
        messageCounter += 1
    }
    
    func add(connectionId: ConnectionController.ID, playerId: UUID) {
        connectIDPlayers[connectionId] = playerId
    }
    
    func reset(seenCounter: Int) {
        self.seenCounter = seenCounter
    }
}

//final class MasterController: Sendable {
//    unowned let root: GameRoot!
//    let gameModel: MasterControllerModel
//    
//    @MainActor
//    init(root: GameRoot, asProxy: Bool) {
//        self.root = root
//        self.gameModel = MasterControllerModel()
//        gameModel.asProxy = asProxy
//        
//        Task {
//            if asProxy {
//                await root.networkProxyStore.model.setMaster(delegate: self)
//            } else {
//                await root.networkStore.model.setMaster(delegate: self)
//            }
//        }
//        Logger.networking.debug("MasterController: Init")
//    }
//    
//    deinit {
//        Logger.networking.debug("MasterController: Deinit")
//    }
//}
//
//// MARK: - Control
//
//extension MasterController {
//    @MainActor
//    func start() async {
//        Logger.networking.debug("MasterController: Start")
//        await root.networkStore.startMasterGame(game: root.gameModel.gameConfig, titleImage: root.adventureRoot.titleImage(for: root.gameModel.gameConfig.master.adventureId!))
//        await root.networkProxyStore.startProxyServer()
//    }
//    
//    @MainActor
//    func stop() async {
//        Logger.networking.debug("MasterController: Stop")
//        await root.networkStore.stopGame()
//        await root.networkProxyStore.stopGame()
//        root.adventureRoot.gameControllable.resetGame()
//        root.gameModel.gameConfig.players = []
//        root.gameModel.gameConfig.controls = []
//    }
//    
//    func resetPlayers() async {
//        var players = await root.gameModel.gameConfig.controls.compactMap { $0.show ? $0.id : nil }.sorted()
//        if await gameModel.asProxy {
//            await players.append(root.gameModel.gameConfig.master.id)
//            players = players.sorted()
//        }
//        await root.audioRoot.gameControllable.gameModel.setCurrent(players: players)
//        var playerNames = await root.gameModel.gameConfig.players.filter { $0.type != .observer }.map { $0.name }.sorted()
//        if await gameModel.asProxy {
//            await playerNames.append(root.gameModel.gameConfig.master.name)
//            playerNames = playerNames.sorted()
//        }
//        await root.diceRoot.gameControllable.resetPlayerDice(to: playerNames)
//        if await !gameModel.asProxy {
//            await root.mapRoot.gameControllable.resetPlayerPins(for: root.gameModel.gameConfig.players.filter { $0.type != .observer })
//        }
//    }
//}
//
//// MARK: - Send Messages
//
//extension MasterController {
//    func show(for idType: NetworkCodableDataType) async {
//        await send(type: .reveal, subtype: .show, updated: idType)
//    }
//    
//    func game(message: NetworkCodableDataType, actionType: RPGMessageActionType) async {
//        await send(type: .update, subtype: actionType, updated: message)
//    }
//    
//    func send(updated: NetworkCodableDataType) async {
//        await send(type: .store, subtype: .store, updated: updated)
//    }
//    
//    func send(type: RPGMessageType, subtype: RPGMessageActionType, updated: NetworkCodableDataType, connectionId: ConnectionController.ID? = nil) async {
//        let counter = "\(await gameModel.messageCounter)"
//        Logger.networking.debug("MasterController: Send \(counter, privacy: .public): \(type.debugDescription, privacy: .public) - \(subtype.debugDescription, privacy: .public) for \(updated.type.token, privacy: .public) -> \(updated.id, privacy: .public)")
//        
//        let game = await root.gameModel.gameConfig
//        let networtData = await GameNetworkModel(counter: gameModel.messageCounter, proxyCounter: 0, type: type, subType: subtype, gameConfig: game, data: updated)
//        
//        await root.logGameController.addMessage(counter: gameModel.messageCounter, type: type, subType: subtype, module: updated.type, itemId: updated.id)
//        await gameModel.increaseMessageCounter()
//        
//        if await gameModel.asProxy {
//            if let connectionId {
//                await root.networkProxyStore.sendPlayer(networtData, to: connectionId)
//            } else {
//                await root.networkProxyStore.sendPlayer(data: networtData)
//            }
//        } else {
//            await root.networkStore.sendPlayer(data: networtData, fileJournal: networtData.type == .reveal)
//        }
//    }
//}
//
//// MARK: - MasterNetworkStoreDelegate
//
//extension MasterController: MasterNetworkStoreDelegate {
//    func ready(for connectionId: ConnectionController.ID) async {
//        Logger.networking.debug("MasterController: Ready for \(connectionId, privacy: .public)")
//    }
//    
//    func lostPlayer(for connectionId: ConnectionController.ID) async {
//        Logger.networking.debug("MasterController: Lost Player for \(connectionId, privacy: .public)")
//        guard let playerId = await gameModel.connectIDPlayers[connectionId] else { return }
//        if await root.gameModel.remove(playerId: playerId) {
//            await resetPlayers()
//        }
//    }
//    
//    func received(_ model: GameNetworkModel, connectionId: ConnectionController.ID?) async {
//        await receivedProcess(model, connectionId: connectionId)
//    }
//    
//    func receivedProcess(_ model: GameNetworkModel, connectionId: ConnectionController.ID?) async {
//        Logger.networking.debug("MasterController: Received \(model.counter, privacy: .public): \(model.type.debugDescription, privacy: .public) - \(model.subType.debugDescription, privacy: .public), \(model.data.type.token, privacy: .public) id: \(model.data.id, privacy: .public)")
//        
//        await root.logGameController.updateMessage(counter: model.counter, player: model.gameConfig.id)
//        if let connectionId {
//            await gameModel.add(connectionId: connectionId, playerId: model.gameConfig.id)
//        }
//        
//        let gameConfigModel = model.gameConfig
//        if await root.gameModel.add(playerId: gameConfigModel.id, playerModel: gameConfigModel.player, sharingModel: SharingControlModel(id: gameConfigModel.id, name: gameConfigModel.name, show: true)) {
//            await resetPlayers()
//        }
//        let seenCounter = await gameModel.seenCounter
//        
//        guard model.counter == 0 || seenCounter < model.counter else {
//            Logger.networking.debug("MasterController: Answered already \(model.counter, privacy: .public): \(model.type.debugDescription, privacy: .public) - \(model.subType.debugDescription, privacy: .public), \(model.data.type.token, privacy: .public)")
//            return
//        }
//        
//        if model.subType != .ok && model.subType != .failed && model.counter > 0 {
//            await gameModel.reset(seenCounter: model.counter)
//        }
//        
//        if await gameModel.asProxy {
//            if model.data.type == .dice && model.type == .update {
//                _ = await root.diceRoot.gameControllable.addGameDiceResult(data: model.data, name: root.gameModel.gameConfig.name, isGameMaster: model.gameConfig.type == .master)
//                let sendData = await GameNetworkModel(counter: model.counter, proxyCounter: model.proxyCounter, type: model.type, subType: model.subType, gameConfig: root.gameModel.gameConfig, data: model.data)
//                await root.networkStore.sendMaster(data: sendData, fileJournal: false)
//            } else {
//                await root.networkStore.sendMaster(data: model, fileJournal: false)
//            }
//        } else if let requestedData = try? await handle(model) {
//            await send(type: model.type, subtype: model.subType, updated: requestedData)
//        }
//    }
//    
//    func receivedFile(_ model: GameNetworkModel) async {
//        Logger.networking.debug("MasterController: FILE Received \(model.counter, privacy: .public): \(model.type.debugDescription, privacy: .public) - \(model.subType.debugDescription, privacy: .public), \(model.data.type.token, privacy: .public) id: \(model.data.id, privacy: .public)")
//        guard await root.gameModel.gameConfig.type != model.gameConfig.type else { return }
//        await received(model, connectionId: nil)
//    }
//}
//
//extension MasterController {
//    func handle(_ model: GameNetworkModel) async throws -> NetworkCodableDataType? {
//        switch model.data.type {
//        case .adventure, .none, .setting, .editor:
//            Logger.networking.error("MasterController: Request \(model.type.debugDescription, privacy: .public) but model request data is not supported. \(model.debugDescription, privacy: .public)")
//            return nil
//        case .audio:
//            return try await handleAudio(model)
//        case .dice:
//            return try await handleDice(model)
//        case .game:
//            return try await handleGame(model)
//        case .map:
//            return try await handleMap(model)
//        case .pdf:
//            return try await handlePdf(model)
//        case .photo:
//            return try await handlePhoto(model)
//        case .table:
//            return try await handleTable(model)
//        case .value:
//            return try await handleValue(model)
//        case .weather:
//            return try await handleWeather(model)
//        case .space:
//            return try await handleSpace(model)
//        @unknown default:
//            fatalError()
//        }
//    }
//    
//    func handleAudio(_ model: GameNetworkModel) async throws -> NetworkCodableDataType? {
//        guard model.subType != .ok && model.subType != .failed else {
//            await root.audioRoot.gameControllable.report(itemId: model.data.id, for: model.gameConfig.id)
//            await send(type: .update, subtype: .audioList, updated: root.audioRoot.gameControllable.audioList(allPlayers: true, with: root.gameModel.gameConfig.id))
//            return nil
//        }
//        switch model.type {
//        case .reveal, .store:
//            return try await root.audioRoot.gameControllable.createGameData(for: model.data.id)
//        case .update:
//            switch model.subType {
//            case .generic:
//                try await root.audioRoot.gameControllable.updateGame(data: model.data, hide: false, deep: false)
//                await send(type: .reveal, subtype: .show, updated: model.data)
//            case .playAudio:
//                return model.data
//            case .audioList:
//                await root.audioRoot.gameControllable.applyAudioList(data: model.data, for: model.gameConfig.id)
//                await send(type: .update, subtype: .audioList, updated: root.audioRoot.gameControllable.audioList(allPlayers: true, with: root.gameModel.gameConfig.id))
//            default:
//                break
//            }
//            return nil
//        }
//    }
//    
//    func handleDice(_ model: GameNetworkModel) async throws -> NetworkCodableDataType? {
//        guard model.subType != .ok && model.subType != .failed && model.gameConfig.type != .observer else { return nil }
//        
//        switch model.type {
//        case .reveal, .store:
//            return try await root.diceRoot.gameControllable.createGameData(for: model.data.id)
//        case .update:
//            let (diceResult, resultCategory) = await root.diceRoot.gameControllable.addGameDiceResult(data: model.data, name: model.gameConfig.name, isGameMaster: model.gameConfig.type == .master)
//            if let diceResult, let resultCategory {
//                await root.tableRoot.gameControllable.addResult(resultCategory, value: diceResult)
//            }
//        }
//        return nil
//    }
//    
//    func handleGame(_ model: GameNetworkModel) async throws -> NetworkCodableDataType? {
//        await root.logGameController.updateScreen(counter: model.counter, player: model.gameConfig.id, data: model.data.data)
//        return nil
//    }
//    
//    func handleMap(_ model: GameNetworkModel) async throws -> NetworkCodableDataType? {
//        guard model.subType != .ok && model.subType != .failed else {
//            await root.mapRoot.gameControllable.report(itemId: model.data.id, for: model.gameConfig.id)
//            return nil
//        }
//        
//        switch model.type {
//        case .reveal:
//            let mapData = try await root.mapRoot.gameControllable.createGameData(for: model.data.id)
//            if model.subType == .mapState {
//                await send(type: .reveal, subtype: .store, updated: mapData)
//                await send(type: .update, subtype: .mapState, updated: model.data)
//            } else {
//                return mapData
//            }
//        case .store:
//            break
//        case .update:
//            guard model.gameConfig.type != .observer else { return nil }
//            switch model.subType {
//            case .mapState:
//                // never get from players mapState updates, only as resend from SharePlay?
//                break
//            case .mapPin:
//                await root.mapRoot.gameControllable.updatePin(itemId: model.data.id, data: model.data.data, playerId: model.gameConfig.id)
//                await send(type: .update, subtype: .mapState, updated: root.mapRoot.gameControllable.networkMapUpdate(for: model.data.id))
//            default:
//                break
//            }
//        }
//        return nil
//    }
//
//    func handlePdf(_ model: GameNetworkModel) async throws -> NetworkCodableDataType? {
//        guard model.subType != .ok && model.subType != .failed else {
//            await root.pdfRoot.gameControllable.report(itemId: model.data.id, for: model.gameConfig.id)
//            return nil
//        }
//
//        switch model.type {
//            case .reveal, .store:
//                return try await root.pdfRoot.gameControllable.createGameData(for: model.data.id)
//            case .update:
//                try await root.pdfRoot.gameControllable.updateGame(data: model.data, hide: false, deep: false)
//                await send(type: .reveal, subtype: .show, updated: model.data)
//                return nil
//        }
//    }
//
//    func handlePhoto(_ model: GameNetworkModel) async throws -> NetworkCodableDataType? {
//        guard model.subType != .ok && model.subType != .failed else {
//            await root.photoRoot.gameControllable.report(itemId: model.data.id, for: model.gameConfig.id)
//            return nil
//        }
//        
//        switch model.type {
//        case .reveal, .store:
//            return try await root.photoRoot.gameControllable.createGameData(for: model.data.id)
//        case .update:
//            try await root.photoRoot.gameControllable.updateGame(data: model.data, hide: false, deep: false)
//            await send(type: .reveal, subtype: .show, updated: model.data)
//            return nil
//        }
//    }
//    
//    func handleTable(_ model: GameNetworkModel) async throws -> NetworkCodableDataType? {
//        guard model.subType != .ok && model.subType != .failed else {
//            await root.tableRoot.gameControllable.report(itemId: model.data.id, for: model.gameConfig.id)
//            return nil
//        }
//        
//        switch model.type {
//        case .reveal, .store:
//            return try await root.tableRoot.gameControllable.createGameData(for: model.data.id)
//        case .update:
//            break
//        }
//        return nil
//    }
//
//    func handleValue(_ model: GameNetworkModel) async throws -> NetworkCodableDataType? {
//        guard model.subType != .ok && model.subType != .failed else {
//            await root.valueRoot.gameControllable.report(itemId: model.data.id, for: model.gameConfig.id)
//            return nil
//        }
//
//        switch model.type {
//        case .reveal, .store:
//            return try await root.valueRoot.gameControllable.createGameData(for: model.data.id)
//        case .update:
//            guard model.gameConfig.type != .observer else { return nil }
//            try await root.valueRoot.gameControllable.updatePlayer(data: model.data)
//            if let characterId = model.gameConfig.player.characterId {
//                await root.mapRoot.gameControllable.setPlayerPin(for: model.gameConfig.id, name: model.gameConfig.name, characterId: characterId)
//            }
//        }
//        return nil
//    }
//    
//    func handleWeather(_ model: GameNetworkModel) async throws -> NetworkCodableDataType? {
//        guard model.subType != .ok && model.subType != .failed else {
//            await root.weatherRoot.gameControllable.report(itemId: model.data.id, for: model.gameConfig.id)
//            return nil
//        }
//        return try await root.weatherRoot.gameControllable.createGameData(for: model.data.id)
//    }
//    
//    func handleSpace(_ model: GameNetworkModel) async throws -> NetworkCodableDataType? {
//        guard model.subType != .ok && model.subType != .failed else {
//            await root.spaceRoot.gameControllable.report(itemId: model.data.id, for: model.gameConfig.id)
//            return nil
//        }
//        switch model.type {
//        case .reveal, .store:
//            return try await root.spaceRoot.gameControllable.createGameData(for: model.data.id)
//        case .update:
//                try await root.spaceRoot.gameControllable.updateGame(data: model.data, hide: false, deep: false)
//                await send(type: .reveal, subtype: .show, updated: model.data)
//            return nil
//        }
//    }
//}
//
//// MARK: - MasterNetworkProxyStoreDelegate
//
//extension MasterController: MasterNetworkProxyControllerDelegate {
//    func readyProxy(for connectionId: ConnectionController.ID) async {
//        Logger.networking.debug("MasterController: Proxy Ready for \(connectionId, privacy: .public)")
//        guard let characterId = await root.gameModel.gameConfig.player.characterId else { return }
//        if let data = try? await root.valueRoot.gameControllable.createGameData(for: characterId) {
//            await send(type: .update, subtype: .store, updated: data, connectionId: connectionId)
//        }
//    }
//    
//    func receivedServerProxy(_ model: GameNetworkModel) async {
//        Logger.networking.debug("MasterController: Proxy Received \(model.counter, privacy: .public)/\(model.proxyCounter, privacy: .public): \(model.type.debugDescription, privacy: .public) - \(model.subType.debugDescription, privacy: .public), \(model.data.type.token, privacy: .public) id: \(model.data.id, privacy: .public)")
//        await receivedProcess(model, connectionId: nil)
//    }
//}
