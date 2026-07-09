// @copyright André Trettin

import AdventureRPG
import CoreRPG
import DiceRPG
import Foundation
import os.log
import AudioRPG
import MapRPG
import PhotoRPG
import TableRPG
import CharacterRPG
import WeatherRPG
import PdfRPG
import SpaceRPG

@MainActor @Observable
final class MasterControllerModel: Sendable {
    var messageCounter: Int = 0
    var connectIDPlayers: [ConnectionController.ID: UUID] = [:]
    var asProxy = false
    
    /// Reserves the next counter atomically. Reading and incrementing in separate
    /// calls lets concurrent sends stamp the same counter, which the receivers'
    /// deduplication then treats as one message.
    func nextMessageCounter() -> Int {
        defer { messageCounter += 1 }
        return messageCounter
    }

    func add(connectionId: ConnectionController.ID, playerId: UUID) {
        // Evict any stale entry for this player from a previous connection,
        // so lostPlayer(oldConnectionId) doesn't remove a player who has already reconnected.
        connectIDPlayers = connectIDPlayers.filter { $0.value != playerId }
        connectIDPlayers[connectionId] = playerId
    }
}

final class MasterController: Sendable {
    // Strong on purpose: an intentional, temporary cycle GameRoot → GameModel →
    // MasterController → GameRoot that stopGame() breaks by dropping the controllers.
    // `unowned` crashed here: delayed tasks (e.g. sendCharacter's 5s sleep) can
    // outlive stopGame()/teardown and would read a destroyed GameRoot. A strong
    // reference keeps GameRoot alive until the last in-flight task finishes.
    let root: GameRoot
    let gameModel: MasterControllerModel
    let asProxy: Bool
    let messagePipeline = GameMessagePipeline()

    @MainActor
    init(root: GameRoot, asProxy: Bool) {
        self.root = root
        self.asProxy = asProxy
        self.gameModel = MasterControllerModel()
        gameModel.asProxy = asProxy

        if asProxy {
            root.networkProxyStore.model.setProxyMasterDelegate(self)
        } else {
            root.networkStore.model.setMasterDelegate(self)
        }
        Logger.networking.debug("MasterController: Init")
    }
    
    deinit {
        Logger.networking.debug("MasterController: Deinit")
    }
}

// MARK: - Control

extension MasterController {
    @MainActor
    func start() async {
        Logger.networking.debug("MasterController: Start")
        await root.networkStore.startMasterGame(game: root.gameModel.gameConfig, titleImage: root.adventureRoot.titleImage(for: root.gameModel.gameConfig.master.adventureId!))
        root.networkProxyStore.startProxyServer()
    }
    
    @MainActor
    func stop() async {
        Logger.networking.debug("MasterController: Stop")
        await messagePipeline.cancelAll()
        await root.networkStore.stopGame()
        await root.networkProxyStore.stopGame()
        await root.adventureRoot.adventureGameControllable.resetGame()
        root.gameModel.gameRoster.players = []
        root.gameModel.gameControl.controls = []
    }
    
    func resetPlayers() async {
        let (gameConfig, gameRoster, gameControl) = await MainActor.run {
            (root.gameModel.gameConfig, root.gameModel.gameRoster, root.gameModel.gameControl)
        }

        var players = gameControl.controls.compactMap { $0.show ? $0.id : nil }.sorted()
        if asProxy {
            players.append(gameConfig.master.id)
            players.sort()
        }
        await root.audioRoot.gameControllable.gameModel.setCurrent(players: players)

        var playerNames = gameRoster.players.filter { $0.type != .observer }.map { $0.name }.sorted()
        if asProxy {
            playerNames.append(gameConfig.master.name)
            playerNames.sort()
        }
        await root.diceRoot.diceGameControllable.resetPlayerDice(to: playerNames)
        if !asProxy {
            await root.mapRoot.mapGameControllable.resetPlayerPins(for: gameRoster.players.filter { $0.type != .observer })
        }
    }
}

// MARK: - Send Messages

extension MasterController {
    func show(for idType: NetworkCodableDataType) async {
        await send(type: .reveal, subtype: .show, updated: idType)
    }
    
    func game(message: NetworkCodableDataType, actionType: RPGMessageActionType, playerId: UUID? = nil) async {
        await send(type: .update, subtype: actionType, updated: message, playerId: playerId)
    }
    
    func send(updated: NetworkCodableDataType) async {
        await send(type: .store, subtype: .store, updated: updated)
    }
    
    func send(type: RPGMessageType, subtype: RPGMessageActionType, updated: NetworkCodableDataType, connectionId: ConnectionController.ID? = nil, playerId: UUID? = nil) async {
        let counter = await gameModel.nextMessageCounter()
        Logger.networking.debug("MasterController: Send \(counter, privacy: .public): \(type.debugDescription, privacy: .public) - \(subtype.debugDescription, privacy: .public) for \(updated.type.token, privacy: .public) -> \(updated.id, privacy: .public)")

        // Snapshot in one MainActor hop so the message never carries a torn
        // combination of config, roster and controls from a concurrent update.
        let (game, roster, currentControl) = await MainActor.run {
            (root.gameModel.gameConfig, root.gameModel.gameRoster, root.gameModel.gameControl)
        }
        var control = currentControl
        if let playerId {
            control.controls = control.controls.filter { $0.id == playerId }
        }
        let networtData = GameNetworkModel(counter: counter, proxyCounter: 0, type: type, subType: subtype, gameConfig: game, gameRoster: roster, gameControl: control, data: updated)

        await root.logGameController.addMessage(counter: counter, type: type, subType: subtype, module: updated.type, itemId: updated.id)

        if asProxy {
            if let connectionId {
                await root.networkProxyStore.sendPlayer(networtData, to: connectionId)
            } else {
                await root.networkProxyStore.sendPlayer(data: networtData)
            }
        } else {
            await root.networkStore.sendPlayer(data: networtData, fileJournal: networtData.type == .reveal)
        }
    }
}

// MARK: - MasterNetworkStoreDelegate

extension MasterController: MasterNetworkStoreDelegate {
    func ready(for connectionId: ConnectionController.ID) async {
        Logger.networking.debug("MasterController: Ready for \(connectionId, privacy: .public)")
    }
    
    func lostPlayer(for connectionId: ConnectionController.ID) async {
        Logger.networking.debug("MasterController: Lost Player for \(connectionId, privacy: .public)")
        guard let playerId = await gameModel.connectIDPlayers[connectionId] else { return }
        if await root.gameModel.remove(playerId: playerId) {
            await resetPlayers()
        }
    }
    
    func received(_ model: GameNetworkModel, connectionId: ConnectionController.ID?) async {
        await receivedProcess(model, connectionId: connectionId)
    }
    
    func receivedProcess(_ model: GameNetworkModel, connectionId: ConnectionController.ID?) async {
        Logger.networking.debug("MasterController: Received \(model.counter, privacy: .public): \(model.type.debugDescription, privacy: .public) - \(model.subType.debugDescription, privacy: .public), \(model.data.type.token, privacy: .public) id: \(model.data.id, privacy: .public)")

        let event = GameMessageEvent(model: model, origin: .direct(connectionId))
        guard await messagePipeline.enqueue(event) else {
            Logger.networking.debug("MasterController: Duplicate ignored \(model.counter, privacy: .public): \(model.type.debugDescription, privacy: .public) - \(model.subType.debugDescription, privacy: .public), \(model.data.type.token, privacy: .public)")
            return
        }
        await processMessages()
    }

    private func processMessages() async {
        while let event = await messagePipeline.next() {
            await process(event)
            await messagePipeline.processed()
        }
    }

    private func process(_ event: GameMessageEvent) async {
        let model = event.model

        await root.logGameController.updateMessage(counter: model.counter, player: model.gameConfig.id)
        if let connectionId = event.connectionId {
            await gameModel.add(connectionId: connectionId, playerId: model.gameConfig.id)
        }
        
        if await root.gameModel.add(playerId: model.gameConfig.id, playerModel: model.gameConfig.player(in: model.gameRoster), sharingModel: SharingControlModel(id: model.gameConfig.id, name: model.senderName, show: true)) {
            await resetPlayers()
        }

        if asProxy {
            if model.data.type == .dice && model.type == .update {
                _ = await root.diceRoot.diceGameControllable.addGameDiceResult(data: model.data, name: root.gameModel.gameName, isGameMaster: model.gameConfig.isMaster)
                let sendData = await GameNetworkModel(counter: model.counter, proxyCounter: model.proxyCounter, type: model.type, subType: model.subType, gameConfig: root.gameModel.gameConfig, gameRoster: root.gameModel.gameRoster, gameControl: root.gameModel.gameControl, data: model.data)
                await root.networkStore.sendMaster(data: sendData, fileJournal: false)
            } else {
                await root.networkStore.sendMaster(data: model, fileJournal: false)
            }
        } else if let requestedData = try? await handle(model) {
            await send(type: model.type, subtype: model.subType, updated: requestedData)
        }
    }
    
    func receivedFile(_ model: GameNetworkModel) async {
        Logger.networking.debug("MasterController: FILE Received \(model.counter, privacy: .public): \(model.type.debugDescription, privacy: .public) - \(model.subType.debugDescription, privacy: .public), \(model.data.type.token, privacy: .public) id: \(model.data.id, privacy: .public)")
        guard await root.gameModel.gameConfig.isMaster != model.gameConfig.isMaster else { return }
        guard await messagePipeline.enqueue(GameMessageEvent(model: model, origin: .file)) else {
            Logger.networking.debug("MasterController: Duplicate file ignored \(model.counter, privacy: .public): \(model.type.debugDescription, privacy: .public) - \(model.subType.debugDescription, privacy: .public), \(model.data.type.token, privacy: .public)")
            return
        }
        await processMessages()
    }
}

extension MasterController {
    func handle(_ model: GameNetworkModel) async throws -> NetworkCodableDataType? {
        switch model.data.type {
        case .adventure, .none, .setting, .editor, .generator, .search:
            Logger.networking.error("MasterController: Request \(model.type.debugDescription, privacy: .public) but model request data is not supported. \(model.debugDescription, privacy: .public)")
            return nil
        case .audio:
            return try await handleAudio(model)
        case .dice:
            return try await handleDice(model)
        case .game:
            return try await handleGame(model)
        case .map:
            return try await handleMap(model)
        case .pdf:
            return try await handlePdf(model)
        case .photo:
            return try await handlePhoto(model)
        case .table:
            return try await handleTable(model)
        case .value:
            return try await handleValue(model)
        case .weather:
            return try await handleWeather(model)
        case .space:
            return try await handleSpace(model)
        @unknown default:
            fatalError()
        }
    }
    
    func handleAudio(_ model: GameNetworkModel) async throws -> NetworkCodableDataType? {
        guard model.subType != .ok && model.subType != .failed else {
            await root.audioRoot.gameControllable.report(itemId: model.data.id, for: model.gameConfig.id)
            await send(type: .update, subtype: .audioList, updated: root.audioRoot.audioGameControllable.audioList(allPlayers: true, with: root.gameModel.gameConfig.id))
            return nil
        }
        switch model.type {
        case .reveal, .store:
            return try await root.audioRoot.gameControllable.createGameData(for: model.data.id)
        case .update:
            switch model.subType {
            case .generic:
                try await root.audioRoot.gameControllable.updateGame(data: model.data, hide: false, deep: false)
                await send(type: .reveal, subtype: .show, updated: model.data)
            case .playAudio:
                // Master must also play so it participates; returning model.data echoes
                // the command to all players (non-SharePlay path).
                let _ = await root.audioRoot.audioGameControllable.play(with: model.data).result
                return model.data
            case .audioList:
                await root.audioRoot.audioGameControllable.applyAudioList(data: model.data, for: model.gameConfig.id)
                await send(type: .update, subtype: .audioList, updated: root.audioRoot.audioGameControllable.audioList(allPlayers: true, with: root.gameModel.gameConfig.id))
            default:
                break
            }
            return nil
        }
    }
    
    func handleDice(_ model: GameNetworkModel) async throws -> NetworkCodableDataType? {
        guard model.subType != .ok && model.subType != .failed && model.senderType != .observer else { return nil }

        switch model.type {
        case .reveal, .store:
            return try await root.diceRoot.gameControllable.createGameData(for: model.data.id)
        case .update:
            let (diceResult, resultCategory) = await root.diceRoot.diceGameControllable.addGameDiceResult(data: model.data, name: model.senderName, isGameMaster: model.gameConfig.isMaster)
            if let diceResult, let resultCategory {
                await root.tableRoot.tableGameControllable.addResult(resultCategory, value: diceResult)
            }
        }
        return nil
    }
    
    func handleGame(_ model: GameNetworkModel) async throws -> NetworkCodableDataType? {
        await root.logGameController.updateScreen(counter: model.counter, player: model.gameConfig.id, data: model.data.data)
        return nil
    }
    
    func handleMap(_ model: GameNetworkModel) async throws -> NetworkCodableDataType? {
        guard model.subType != .ok && model.subType != .failed else {
            await root.mapRoot.gameControllable.report(itemId: model.data.id, for: model.gameConfig.id)
            return nil
        }
        
        switch model.type {
        case .reveal:
            let mapData = try await root.mapRoot.gameControllable.createGameData(for: model.data.id)
            if model.subType == .mapState {
                await send(type: .reveal, subtype: .store, updated: mapData)
                // Send the live map state (not the request echo, whose data is
                // nil) so the recovering player syncs room visibility and pins.
                // Targeted: the other players are already up to date.
                await send(type: .update, subtype: .mapState, updated: root.mapRoot.mapGameControllable.networkMapUpdate(for: model.data.id), playerId: model.gameConfig.id)
            } else {
                return mapData
            }
        case .store:
            break
        case .update:
            guard model.senderType != .observer else { return nil }
            switch model.subType {
            case .mapState:
                // never get from players mapState updates, only as resend from SharePlay?
                break
            case .mapPin:
                await root.mapRoot.mapGameControllable.updatePin(itemId: model.data.id, data: model.data.data, playerId: model.gameConfig.id)
                await send(type: .update, subtype: .mapState, updated: root.mapRoot.mapGameControllable.networkMapUpdate(for: model.data.id))
            default:
                break
            }
        }
        return nil
    }

    func handlePdf(_ model: GameNetworkModel) async throws -> NetworkCodableDataType? {
        guard model.subType != .ok && model.subType != .failed else {
            await root.pdfRoot.gameControllable.report(itemId: model.data.id, for: model.gameConfig.id)
            return nil
        }

        switch model.type {
            case .reveal, .store:
                return try await root.pdfRoot.gameControllable.createGameData(for: model.data.id)
            case .update:
                try await root.pdfRoot.gameControllable.updateGame(data: model.data, hide: false, deep: false)
                await send(type: .reveal, subtype: .show, updated: model.data)
                return nil
        }
    }

    func handlePhoto(_ model: GameNetworkModel) async throws -> NetworkCodableDataType? {
        guard model.subType != .ok && model.subType != .failed else {
            await root.photoRoot.gameControllable.report(itemId: model.data.id, for: model.gameConfig.id)
            return nil
        }
        
        switch model.type {
        case .reveal, .store:
            return try await root.photoRoot.gameControllable.createGameData(for: model.data.id)
        case .update:
            try await root.photoRoot.gameControllable.updateGame(data: model.data, hide: false, deep: false)
            await send(type: .reveal, subtype: .show, updated: model.data)
            return nil
        }
    }
    
    func handleTable(_ model: GameNetworkModel) async throws -> NetworkCodableDataType? {
        guard model.subType != .ok && model.subType != .failed else {
            await root.tableRoot.gameControllable.report(itemId: model.data.id, for: model.gameConfig.id)
            return nil
        }
        
        switch model.type {
        case .reveal, .store:
            return try await root.tableRoot.gameControllable.createGameData(for: model.data.id)
        case .update:
            break
        }
        return nil
    }

    func handleValue(_ model: GameNetworkModel) async throws -> NetworkCodableDataType? {
        guard model.subType != .ok && model.subType != .failed else {
            await root.characterRoot.gameControllable.report(itemId: model.data.id, for: model.gameConfig.id)
            return nil
        }

        switch model.type {
        case .reveal, .store:
            return try await root.characterRoot.gameControllable.createGameData(for: model.data.id)
        case .update:
            guard model.senderType != .observer else { return nil }
            try await root.characterRoot.valueGameControllable.updatePlayer(data: model.data)
            if let characterId = model.gameConfig.player(in: model.gameRoster).characterId {
                await root.mapRoot.mapGameControllable.setPlayerPin(for: model.gameConfig.id, name: model.senderName, characterId: characterId)
            }
        }
        return nil
    }
    
    func handleWeather(_ model: GameNetworkModel) async throws -> NetworkCodableDataType? {
        guard model.subType != .ok && model.subType != .failed else {
            await root.weatherRoot.gameControllable.report(itemId: model.data.id, for: model.gameConfig.id)
            return nil
        }
        return try await root.weatherRoot.gameControllable.createGameData(for: model.data.id)
    }
    
    func handleSpace(_ model: GameNetworkModel) async throws -> NetworkCodableDataType? {
        guard model.subType != .ok && model.subType != .failed else {
            await root.spaceRoot.gameControllable.report(itemId: model.data.id, for: model.gameConfig.id)
            return nil
        }
        switch model.type {
        case .reveal, .store:
            return try await root.spaceRoot.gameControllable.createGameData(for: model.data.id)
        case .update:
            if model.subType == .spaceTransform {
                // Manipulation sync from a player — apply locally only; the network
                // layer already fanned the message out to the other players.
                try await root.spaceRoot.gameControllable.updateGame(data: model.data, subtype: .spaceTransform)
                return nil
            }
            try await root.spaceRoot.gameControllable.updateGame(data: model.data, hide: false, deep: false)
            await send(type: .reveal, subtype: .show, updated: model.data)
            return nil
        }
    }
}

// MARK: - MasterNetworkProxyStoreDelegate

extension MasterController: MasterNetworkProxyControllerDelegate {
    func readyProxy(for connectionId: ConnectionController.ID) async {
        Logger.networking.debug("MasterController: Proxy Ready for \(connectionId, privacy: .public)")
        guard let characterId = await root.gameModel.gamePlayer.characterId else { return }
        if let data = try? await root.characterRoot.gameControllable.createGameData(for: characterId) {
            await send(type: .update, subtype: .store, updated: data, connectionId: connectionId)
        }
    }
    
    func receivedServerProxy(_ model: GameNetworkModel) async {
        Logger.networking.debug("MasterController: Proxy Received \(model.counter, privacy: .public)/\(model.proxyCounter, privacy: .public): \(model.type.debugDescription, privacy: .public) - \(model.subType.debugDescription, privacy: .public), \(model.data.type.token, privacy: .public) id: \(model.data.id, privacy: .public)")
        guard await messagePipeline.enqueue(GameMessageEvent(model: model, origin: .proxy)) else {
            Logger.networking.debug("MasterController: Duplicate proxy ignored \(model.counter, privacy: .public): \(model.type.debugDescription, privacy: .public) - \(model.subType.debugDescription, privacy: .public), \(model.data.type.token, privacy: .public)")
            return
        }
        await processMessages()
    }
}
