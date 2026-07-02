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
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor @Observable
final class PlayerControllerModel: Sendable {
    var gameUpdateType: NetworkModules = .none
    var messageCounter: Int = 0
    var responseCounter: Int = 0
    var lostMaster: Bool = true
    var hasSendPlayer = false
    var asGameMaster = false
    
    var gameModelMessage = GameModelMessage()

    func increaseMessageCounter() {
        messageCounter += 1
    }

    func reset(lostMaster: Bool) {
        self.lostMaster = lostMaster
    }
    
    func reset(sendPlayer: Bool) {
        self.hasSendPlayer = sendPlayer
    }
    
    func setGameUpdateType(_ type: NetworkModules) {
        gameUpdateType = type
    }
}

actor GameModelMessage {
    private var messages: [GameNetworkModel] = []
    private var processing: Bool = false
    
    func append(_ message: GameNetworkModel) {
        messages.append(message)
    }
    
    func next() -> GameNetworkModel? {
        guard !processing && !messages.isEmpty else { return nil }
        processing = true
        return messages.removeFirst()
    }
    
    func processed() {
        processing = false
    }
}

final class PlayerController: Sendable {
    // unowned (not strong) to break the cycle GameRoot → GameModel → PlayerController → GameRoot;
    // GameModel always drops its controllers before GameRoot can go away (stopGame()).
    unowned let root: GameRoot
    let gameModel: PlayerControllerModel
    let proxyMasterController: MasterController?
    
    @MainActor
    init(root: GameRoot, asGameMaster: Bool) {
        self.root = root
        self.gameModel = PlayerControllerModel()
        self.gameModel.asGameMaster = asGameMaster
        
        if asGameMaster {
            proxyMasterController = nil
            Task {
                await root.networkStore.setupLocal()
            }
        } else {
            proxyMasterController = MasterController(root: root, asProxy: true)
        }
        root.networkStore.model.setPlayerDelegate(self)
        root.networkProxyStore.model.setProxyPlayerDelegate(self)
        Logger.networking.debug("PlayerController: Init")
    }
    
    deinit {
        Logger.networking.debug("PlayerController: Deinit")
    }
}

// MARK: - Control

extension PlayerController {
    @MainActor
    func start(to model: BrowserGameModel?) async -> Bool {
        Logger.networking.debug("PlayerController: Start")
        if root.gameModel.gameType == .player {
            root.networkProxyStore.startProxyServer()
        } else if root.gameModel.gameType == .proxy {
            return await root.networkProxyStore.startPlayerGame(to: model)
        }
        return await root.networkStore.startPlayerGame(to: model)
    }
    
    @MainActor
    func stop() async {
        Logger.networking.debug("PlayerController: Stop")
        await root.networkProxyStore.stopGame()
        await root.networkStore.stopGame()
        root.adventureRoot.adventureGameControllable.resetGame()
        gameModel.hasSendPlayer = false
    }
    
    @MainActor
    func resetPlayers() {
        let players = root.gameModel.gameRoster.controls.compactMap { $0.show ? $0.id : nil }
        root.audioRoot.gameControllable.gameModel.currentPlayers = (players + [root.gameModel.gameConfig.master.id]).sorted()
        let playerNames = root.gameModel.gameRoster.controls.map { $0.name }.sorted()
        root.diceRoot.diceGameControllable.resetPlayerDice(to: [root.gameModel.gameConfig.master.name] + playerNames)
    }
}

// MARK: - Send Messages

extension PlayerController {
    func send(updated: NetworkCodableDataType) async {
        await send(counter: 0, type: .store, subType: .store, updated: updated)
    }
    
    func game(message: NetworkCodableDataType, actionType: RPGMessageActionType) async {
        await send(counter: 0, type: .update, subType: actionType, updated: message)
    }
    
    func send(screen: AKImage, responseCounter: Int) async {
        let data = NetworkCodableDataType(id: UUID(), type: .game, version: 0, data: screen.jpegData(compressionQuality: 0.5))
        await send(counter: responseCounter, type: .store, subType: .screen, updated: data)
    }
    
    func send(counter: Int, type: RPGMessageType, subType: RPGMessageActionType = .show, updated: NetworkCodableDataType, useJournal: Bool = false) async {
        Logger.networking.debug("PlayerController: Send \(counter, privacy: .public): \(type.debugDescription, privacy: .public) - \(subType.debugDescription, privacy: .public) for \(updated.id, privacy: .public)")
        let networtData = await GameNetworkModel(counter: counter, proxyCounter: 0, type: type, subType: subType, gameConfig: root.gameModel.gameConfig, gameRoster: root.gameModel.gameRoster, data: updated)
        
        let useOnTypeJournal = useJournal || updated.type == .audio || updated.type == .photo || updated.type == .space
        await send(model: networtData, useJournal: useOnTypeJournal)
    }
    
    private func send(model: GameNetworkModel, useJournal: Bool = false) async {
        if await root.gameModel.gameType == .proxy {
            await root.networkProxyStore.sendMaster(data: model)
        } else {
            await root.networkStore.sendMaster(data: model, fileJournal: useJournal)
            await root.networkProxyStore.sendPlayer(data: model)
        }
    }
}

// MARK: - Send PlayerNetworkStoreDelegate

extension PlayerController: PlayerNetworkStoreDelegate {
    func lostConnection() async {
        Logger.networking.debug("PlayerController: Lost Connection - Reset State")
        await gameModel.reset(lostMaster: true)
        await gameModel.reset(sendPlayer: false)
    }
    
    func ready() async {
        Logger.networking.debug("PlayerController: Ready")
        await gameModel.reset(lostMaster: false)
        await sendCharacter()
    }
    
    func receivedFile(_ model: GameNetworkModel) async {
        Logger.networking.debug("PlayerController: FILE Received \(model.counter, privacy: .public): \(model.type.debugDescription, privacy: .public) - \(model.subType.debugDescription, privacy: .public), \(model.data.type.token, privacy: .public) id: \(model.data.id, privacy: .public)")
        guard await root.gameModel.gameConfig.isMaster != model.gameConfig.isMaster else { return }
        await received(model)
    }
    
    func received(_ model: GameNetworkModel) async {
        await receivedProcess(model, fromProxy: false)
    }
    
    func receivedProcess(_ model: GameNetworkModel, fromProxy: Bool = false) async {
        Logger.networking.debug("PlayerController: Received \(model.counter, privacy: .public): \(model.type.debugDescription, privacy: .public) - \(model.subType.debugDescription, privacy: .public), \(model.data.type.token, privacy: .public) id: \(model.data.id, privacy: .public)")
        
        if await !gameModel.asGameMaster {
            let controls = model.gameRoster.controls
            if model.gameConfig.isMaster {
                await root.gameModel.reset(controls: controls)
                await root.gameModel.reset(master: model.gameConfig.master)
                await root.gameModel.reset(playerId: root.gameModel.gameConfig.id, player: root.gameModel.gamePlayer, players: model.gameRoster.players)
                await root.gameModel.reset(features: model.gameRoster.features)
                await resetPlayers()
            }

            let configName = await root.gameModel.gameName
            let type = await root.gameModel.gameType
            guard type == .proxy || type == .observer || controls.isEmpty || controls.contains(where: { $0.name == configName && $0.show == true }) else {
                Logger.networking.debug("PlayerController: Message will be ignored because of controls \(controls, privacy: .public)")
                return
            }
            guard await root.gameModel.gameType == .proxy || model.gameConfig.isMaster || model.data.type == .dice || model.subType == .spaceTransform else {
                Logger.networking.debug("PlayerController: Message will be ignored because it is send from Player \(model.senderName, privacy: .public)")
                return
            }
        }
        
        if !fromProxy {
            await root.networkProxyStore.sendPlayer(data: model)
            Task { await self.sendCharacter() }
        }
        
        await gameModel.gameModelMessage.append(model)
        await processMessages()
    }
    
    func processMessages() async {
        while let message = await gameModel.gameModelMessage.next() {
            let response = try? await handle(message)
            if let response {
                await send(model: response)
                if response.subType == .ok {
                    await gameModel.increaseMessageCounter()
                }
            } else {
                await gameModel.increaseMessageCounter()
            }
            await gameModel.gameModelMessage.processed()
        }
    }
}

// MARK: - Send PlayerNetworkProxyStoreDelegate

extension PlayerController: PlayerNetworkProxyControllerDelegate {
    func lostProxyConnection() async {
        Logger.networking.debug("PlayerController: Lost Proxy Connection - Reset State")
        await lostConnection()
    }
    
    func readyProxy() async {
        Logger.networking.debug("PlayerController: Proxy Ready")
        await gameModel.reset(lostMaster: false)
    }
    
    func receivedProxy(_ model: GameNetworkModel) async {
        Logger.networking.debug("PlayerController: Proxy Received \(model.counter, privacy: .public) / \(model.proxyCounter, privacy: .public): \(model.type.debugDescription, privacy: .public) - \(model.subType.debugDescription, privacy: .public), \(model.data.type.token, privacy: .public) id: \(model.data.id, privacy: .public)")
        await receivedProcess(model, fromProxy: true)
    }
}

extension PlayerController {
    func handle(_ model: GameNetworkModel) async throws -> GameNetworkModel? {
        switch model.data.type {
        case .none, .game, .setting, .editor, .generator, .search:
            return nil
        case .adventure:
            return handleAdventure(model)
        case .audio:
            return try await handleAudio(model)
        case .dice:
            return try await handleDice(model)
        case .pdf:
            return try await handlePdf(model)
        case .photo:
            return try await handlePhoto(model)
        case .map:
            return try await handleMap(model)
        case .table:
            return try await handleTable(model)
        case .weather:
            return try await handleWeather(model)
        case .value:
            return try await handleValue(model)
        case .space:
            return try await handleSpace(model)
        @unknown default:
            fatalError()
        }
    }
    
    func handleAdventure(_ model: GameNetworkModel) -> GameNetworkModel? {
        nil
    }
    
    func handleAudio(_ model: GameNetworkModel) async throws -> GameNetworkModel? {
        guard model.subType != .ok && model.subType != .failed else {
            await root.audioRoot.gameControllable.report(itemId: model.data.id, for: model.gameConfig.id)
            return nil
        }
        
        switch model.type {
        case .reveal:
            if try await root.audioRoot.gameControllable.reveal(itemId: model.data.id, data: model.data, save: true) {
                await root.audioRoot.audioGameControllable.applyAudio(id: model.data.id, for: [root.gameModel.gameConfig.id, model.gameConfig.id])
                return await response(for: model, isSuccess: true, requestData: false)
            } else {
                return await response(for: model, isSuccess: true, requestData: true)
            }
        case .store:
            try await root.audioRoot.gameControllable.updateGame(data: model.data, hide: model.subType == .store, deep: true)
            return await response(for: model, isSuccess: true, requestData: false)
        case .update:
            switch model.subType {
            case .audioList:
                await root.audioRoot.audioGameControllable.applyAudioList(data: model.data, for: model.gameConfig.id)
            case .playAudio:
                await root.audioRoot.audioGameControllable.applyAudio(id: model.data.id, for: model.gameRoster.controls.map { $0.id } + [model.gameConfig.master.id])
                let isSharePlayActive = await MainActor.run { root.networkStore.sharePlayStore.isActive }
                if isSharePlayActive && !model.gameConfig.isMaster {
                    // SharePlay: AVPlayerPlaybackCoordinator propagates play() from the initiator.
                    // Only load the item here so the coordinator can sync this participant.
                    await root.audioRoot.audioGameControllable.loadPlaylist(id: model.data.id)
                } else {
                    let _ = await root.audioRoot.audioGameControllable.play(with: model.data).result
                }
            default:
                break
            }
        }
        return nil
    }

    func handleDice(_ model: GameNetworkModel) async throws -> GameNetworkModel? {
        let features = await root.gameModel.gameRoster.features
        guard await (root.gameModel.gameName != model.senderName) &&
                (features.diceMaster || !model.gameConfig.isMaster) &&
                (features.dicePlayers || model.gameConfig.isMaster)
        else { return await response(for: model, isSuccess: false, requestData: false) }
        
        switch model.type {
        case .reveal:
            if try await !root.diceRoot.gameControllable.reveal(itemId: model.data.id, data: model.data, save: true) {
                return await response(for: model, isSuccess: true, requestData: true)
            }
        case .store:
            try await root.diceRoot.gameControllable.updateGame(data: model.data, hide: model.subType == .store, deep: model.subType == .show)
        case .update:
            switch model.subType {
            case .show, .store:
                try await root.diceRoot.diceGameControllable.updateGame(data: model.data, hide: model.subType == .store, focus: model.subType == .show)
            case .generic:
                _ = await root.diceRoot.diceGameControllable.addGameDiceResult(data: model.data, name: model.senderName, isGameMaster: model.gameConfig.isMaster)
                break
            default:
                break
            }
        }
        return nil
    }
    
    func handleMap(_ model: GameNetworkModel) async throws -> GameNetworkModel? {
        switch model.type {
        case .reveal:
            if try await root.mapRoot.gameControllable.reveal(itemId: model.data.id, data: model.data, save: false) {
                _ = await root.mapRoot.gameControllable.setCurrent(itemId: model.data.id)
                Task { @MainActor in
                    if gameModel.asGameMaster {
                        gameModel.gameUpdateType = .map
                    }
                }
                return await response(for: model, isSuccess: true, requestData: false)
            } else {
                await MainActor.run {
                    if gameModel.gameUpdateType == .photo {
                        gameModel.gameUpdateType = .none
                    }
                }
                return await response(for: model, isSuccess: true, requestData: true)
            }
        case .store:
            try await root.mapRoot.gameControllable.updateGame(data: model.data, hide: true, deep: true)
            return await response(for: model, isSuccess: true, requestData: false)
        case .update:
            switch model.subType {
            case .mapState:
                if await root.mapRoot.gameControllable.hasItem(id: model.data.id, version: model.data.version) {
                    await root.mapRoot.mapGameControllable.updateMap(for: model.data.id, with: model.data)
                    let missingImages = await root.mapRoot.mapGameControllable.missingPlayerImages(itemId: model.data.id)
                    for idType in missingImages {
                        await send(counter: 0, type: .store, subType: .store, updated: idType)
                    }
                    
                    // Update fog of war on 3D board
                    #if os(visionOS)
                    Task { @MainActor in
                        let isGameMaster = root.gameModel.gameConfig.isMaster
                        await root.gameModel.gameTableModel?.updateFogOfWar(isGameMaster: isGameMaster)
                            root.gameModel.gameTableModel?.syncPawnsWithMapPins()
                    }
                    #endif
                } else {
                    return await GameNetworkModel(counter: model.counter, proxyCounter: model.proxyCounter, type: .reveal, subType: .ok, gameConfig: root.gameModel.gameConfig, data: NetworkCodableDataType(id: model.data.id, type: model.data.type, version: 0, data: nil))
                }
            case .mapPin:
                // master will never send mapPin updates, they come only from players.
                break
            default:
                break
            }
            Task { @MainActor in
                gameModel.gameUpdateType = .map
            }
        }
        return nil
    }

    func handlePdf(_ model: GameNetworkModel) async throws -> GameNetworkModel? {
        switch model.type {
            case .reveal:
                if try await root.pdfRoot.gameControllable.reveal(itemId: model.data.id, data: model.data, save: true) {
                    Task { @MainActor in
                        gameModel.gameUpdateType = .pdf
                    }
                    return await response(for: model, isSuccess: true, requestData: false)
                } else {
                    return await response(for: model, isSuccess: true, requestData: true)
                }
            case .store:
                try await root.pdfRoot.gameControllable.updateGame(data: model.data, hide: model.subType == .store, deep: true)
                return await response(for: model, isSuccess: true, requestData: false)
            case .update:
                break
        }
        return nil
    }

    func handlePhoto(_ model: GameNetworkModel) async throws -> GameNetworkModel? {
        switch model.type {
        case .reveal:
            if try await root.photoRoot.gameControllable.reveal(itemId: model.data.id, data: model.data, save: true) {
                Task { @MainActor in
                    gameModel.gameUpdateType = .photo
                    root.photoRoot.photoGameControllable.resetPhotoSpace()
                }
                
                return await response(for: model, isSuccess: true, requestData: false)
            } else {
                return await response(for: model, isSuccess: true, requestData: true)
            }
        case .store:
            try await root.photoRoot.gameControllable.updateGame(data: model.data, hide: model.subType == .store, deep: true)
            return await response(for: model, isSuccess: true, requestData: false)
        case .update:
            switch model.subType {
            case .photoSpace:
                try await root.photoRoot.gameControllable.updateGame(data: model.data, subtype: model.subType)
            default:
                if model.data.data != nil {
                    try await root.photoRoot.gameControllable.updateGame(data: model.data, hide: model.subType == .store, deep: true)
                }
            }
            let saveTask = Task { @MainActor in
                if await root.photoRoot.gameControllable.setCurrent(itemId: model.data.id) {
                    gameModel.gameUpdateType = .photo
                }
            }
            let _ = await saveTask.result
        }
        return nil
    }
    
    func handleTable(_ model: GameNetworkModel) async throws -> GameNetworkModel? {
        switch model.type {
        case .reveal:
            if try await root.tableRoot.gameControllable.reveal(itemId: model.data.id, data: model.data, save: true) {
                Task { @MainActor in
                    gameModel.gameUpdateType = .table
                }
                return await response(for: model, isSuccess: true, requestData: false)
            } else {
                return await response(for: model, isSuccess: true, requestData: true)
            }
        case .store:
            try await root.tableRoot.gameControllable.updateGame(data: model.data, hide: model.subType == .store, deep: true)
            return await response(for: model, isSuccess: true, requestData: false)
        case .update:
            break
        }
        return nil
    }
    
    func handleValue(_ model: GameNetworkModel) async throws -> GameNetworkModel? {
        guard await root.gameModel.gameType != .proxy else { return try await handleProxyValue(model) }
        guard model.gameConfig.isMaster else { return nil }
        switch model.type {
        case .reveal:
            if try await root.characterRoot.gameControllable.reveal(itemId: model.data.id, data: model.data, save: true) {
                Task { @MainActor in
                    gameModel.gameUpdateType = .value
                }
                return await response(for: model, isSuccess: true, requestData: false)
            } else {
                return await response(for: model, isSuccess: true, requestData: true)
            }
        case .store:
            try await root.characterRoot.gameControllable.updateGame(data: model.data, hide: model.subType == .store, deep: true)
            return await response(for: model, isSuccess: true, requestData: false)
        case .update:
            switch model.subType {
            case .generic:
                if let characterId = await root.gameModel.gamePlayer.characterId {
                    Task { @MainActor in
                        await root.characterRoot.valueGameControllable.addItem(id: model.data.id, data: model.data, for: characterId)
                    }
                }
            case .valueResult:
                if let characterId = await root.gameModel.gamePlayer.characterId {
                    Task { @MainActor in
                        await root.characterRoot.valueGameControllable.add(result: model.data, for: characterId)
                    }
                }
            default:
                Task { @MainActor in
                    if await root.characterRoot.gameControllable.setCurrent(itemId: model.data.id) {
                        gameModel.gameUpdateType = .value
                    }
                }
            }
        }
        return nil
    }
    
    func handleWeather(_ model: GameNetworkModel) async throws -> GameNetworkModel? {
        switch model.type {
        case .reveal:
            if try await root.weatherRoot.gameControllable.reveal(itemId: model.data.id, data: model.data, save: true) {
                Task { @MainActor in
                    gameModel.gameUpdateType = .weather
                }
                return await response(for: model, isSuccess: true, requestData: false)
            } else {
                return await response(for: model, isSuccess: true, requestData: true)
            }
        case .store:
            try await root.weatherRoot.gameControllable.updateGame(data: model.data, hide: model.subType == .store, deep: true)
            return await response(for: model, isSuccess: true, requestData: false)
        case .update:
            Task { @MainActor in
                if await root.weatherRoot.gameControllable.setCurrent(itemId: model.data.id) {
                    gameModel.gameUpdateType = .weather
                }
            }
        }
        return nil
    }
    
    func handleSpace(_ model: GameNetworkModel) async throws -> GameNetworkModel? {
        switch model.type {
        case .reveal:
            if try await root.spaceRoot.gameControllable.reveal(itemId: model.data.id, data: model.data, save: true) {
                Task { @MainActor in
                    gameModel.gameUpdateType = .space

                    #if os(visionOS)
                    if root.networkStore.sharePlayStore.isActive {
                        // Switch the presentation mode; the modeChanged observer
                        // reconfigures the spatial template, and the game screen
                        // opens the immersive space when it shows the space module.
                        root.gameModel.shareState.mode = .immersive
                    }
                    #endif
                }
                return await response(for: model, isSuccess: true, requestData: false)
            } else {
                return await response(for: model, isSuccess: true, requestData: true)
            }
        case .store:
            try await root.spaceRoot.gameControllable.updateGame(data: model.data, hide: model.subType == .store, deep: true)
            return await response(for: model, isSuccess: true, requestData: false)
        case .update:
            if model.subType == .spaceTransform {
                // Manipulation sync (rotate / scale / move) — apply to the shared
                // model state; transport-level fan-out already delivered it to everyone.
                try await root.spaceRoot.gameControllable.updateGame(data: model.data, subtype: .spaceTransform)
                return nil
            }
            Task { @MainActor in
                if await root.spaceRoot.gameControllable.setCurrent(itemId: model.data.id) {
                    gameModel.gameUpdateType = .space
                    
                    // ✅ SharePlay: Update current selection in open immersive space
                    #if os(visionOS)
                    if root.networkStore.sharePlayStore.isActive,
                       root.gameModel.shareState.mode == .immersive {
                        // The immersive space is already open, selection will update via binding
                        Logger.networking.debug("✅ Updated immersive space selection: \(model.data.id, privacy: .public)")
                    }
                    #endif
                }
            }
        }
        return nil
    }
    
    func handleProxyValue(_ model: GameNetworkModel) async throws -> GameNetworkModel? {
        switch model.type {
        case .reveal, .store:
            return nil
        case .update:
            try await root.characterRoot.gameControllable.updateGame(data: model.data, hide: false, deep: true)
            let characterId = model.data.id
            Task {
                _ = await root.characterRoot.gameControllable.setCurrent(itemId: characterId)
                await root.characterRoot.gameControllable.focus(on: characterId)
                try? await Task.sleep(for: .seconds(1))
                await MainActor.run { root.gameModel.selectedCharacter = characterId }
            }
            return nil
        }
    }
    
    nonisolated func response(for model: GameNetworkModel, isSuccess: Bool, requestData: Bool) async -> GameNetworkModel {
        let gameConfig = await root.gameModel.gameConfig
        let gameRoster = await root.gameModel.gameRoster
        if requestData {
            return GameNetworkModel(counter: model.counter, proxyCounter: model.proxyCounter, type: model.type, subType: model.subType, gameConfig: gameConfig, gameRoster: gameRoster, data: model.data)
        }
        return GameNetworkModel(counter: model.counter, proxyCounter: model.proxyCounter, type: model.type, subType: isSuccess ? .ok : .failed, gameConfig: gameConfig, gameRoster: gameRoster, data: NetworkCodableDataType(id: model.data.id, type: model.data.type, version: 0, data: nil))
    }
    
    func sendCharacter() async {
        let gameType = await root.gameModel.gameType
        guard await !gameModel.hasSendPlayer && gameType != .observer, let characterId = await root.gameModel.gamePlayer.characterId else { return }
        await gameModel.reset(sendPlayer: true)

        if let result = try? await root.characterRoot.gameControllable.createGameData(for: characterId) {
            await send(counter: 0, type: .update, subType: .store, updated: result, useJournal: true)
        }
        do {
            try await Task.sleep(for: .seconds(5))
        } catch {
            return
        }
        await sendAudioList()
    }

    func sendAudioList() async {
        await send(counter: 0, type: .update, subType: .audioList, updated: root.audioRoot.audioGameControllable.audioList(allPlayers: false, with: root.gameModel.gameConfig.id), useJournal: false)
    }
}
