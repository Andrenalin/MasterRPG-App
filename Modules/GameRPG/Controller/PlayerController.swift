// @copyright André Trettin

import CoreRPG
import Foundation
import os.log
#if os(macOS)
internal import AppKit
#else
internal import UIKit
#endif

final class PlayerController: Sendable {
    let root: GameRootController
    let gameModel: PlayerControllerModel
    let proxyMasterController: MasterController?
    
    @MainActor
    init(root: GameRootController, asGameMaster: Bool) {
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
        Task {
            await root.networkStore.model.setPlayer(delegate: self)
            await root.networkProxyStore.model.setPlayer(delegate: self)
        }
        Logger.networking.debug("PlayerController: Init")
    }
    
    deinit {
        Logger.networking.debug("PlayerController: Deinit")
    }
}

// MARK: - Control

extension PlayerController {
    @MainActor
    func start(to model: BrowserDeviceModel?) async -> Bool {
        Logger.networking.debug("PlayerController: Start")
        if root.gameModel.gameConfig.type == .player {
            await root.networkProxyStore.startProxyServer()
        } else if root.gameModel.gameConfig.type == .proxy {
            return await root.networkProxyStore.startPlayerGame(to: model)
        }
        return await root.networkStore.startPlayerGame(to: model)
    }
    
    @MainActor
    func stop() async {
        Logger.networking.debug("PlayerController: Stop")
        await root.networkProxyStore.stopGame()
        await root.networkStore.stopGame()
        root.adventureRoot.gameControllable.resetGame()
        gameModel.hasSendPlayer = false
    }
    
    @MainActor
    func resetPlayers() {
        let players = root.gameModel.gameConfig.controls.compactMap { $0.show ? $0.id : nil }
        root.audioRoot.gameControllable.gameModel.currentPlayers = (players + [root.gameModel.gameConfig.master.id]).sorted()
        let playerNames = root.gameModel.gameConfig.controls.map { $0.name }.sorted()
        root.diceRoot.gameControllable.resetPlayerDice(to: [root.gameModel.gameConfig.master.name] + playerNames)
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
        let networtData = await GameNetworkModel(counter: counter, proxyCounter: 0, type: type, subType: subType, gameConfig: root.gameModel.gameConfig, data: updated)
        
        let useOnTypeJournal = useJournal || updated.type == .audio || updated.type == .photo || updated.type == .space
        await send(model: networtData, useJournal: useOnTypeJournal)
    }
    
    private func send(model: GameNetworkModel, useJournal: Bool = false) async {
        if await root.gameModel.gameConfig.type == .proxy {
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
        guard await root.gameModel.gameConfig.type != model.gameConfig.type else { return }
        await received(model)
    }
    
    func received(_ model: GameNetworkModel) async {
        await receivedProcess(model, fromProxy: false)
    }
    
    func receivedProcess(_ model: GameNetworkModel, fromProxy: Bool = false) async {
        Logger.networking.debug("PlayerController: Received \(model.counter, privacy: .public): \(model.type.debugDescription, privacy: .public) - \(model.subType.debugDescription, privacy: .public), \(model.data.type.token, privacy: .public) id: \(model.data.id, privacy: .public)")
        
        if await !gameModel.asGameMaster {
            let controls = model.gameConfig.controls
            if model.gameConfig.type == .master {
                await root.gameModel.reset(controls: controls)
                await root.gameModel.reset(master: model.gameConfig.master)
                await root.gameModel.reset(playerId: root.gameModel.gameConfig.id, player: root.gameModel.gameConfig.player, players: model.gameConfig.players)
                await root.gameModel.reset(features: model.gameConfig.features)
                await resetPlayers()
            }
            
            let configName = await root.gameModel.gameConfig.name
            guard await root.gameModel.gameConfig.type == .proxy || controls.isEmpty || controls.contains(where: { $0.name == configName && $0.show == true }) else {
                Logger.networking.debug("PlayerController: Message will be ignored because of controls \(controls, privacy: .public)")
                return
            }
            guard await root.gameModel.gameConfig.type == .proxy || model.gameConfig.type == .master || model.data.type == .dice else {
                Logger.networking.debug("PlayerController: Message will be ignored because it is send from Player \(model.gameConfig.name, privacy: .public)")
                return
            }
        }
        
        if !fromProxy {
            await root.networkProxyStore.sendPlayer(data: model)
            await sendCharacter()
        }
        
        await gameModel.gameModelMessage.append(model)
        await processMessages()
    }
    
    func processMessages() async {
        if let message = await gameModel.gameModelMessage.next() {
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
            await processMessages()
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
        case .none, .game, .setting, .editor, .search:
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
                await root.audioRoot.gameControllable.applyAudio(id: model.data.id, for: [root.gameModel.gameConfig.id, model.gameConfig.id])
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
                await root.audioRoot.gameControllable.applyAudioList(data: model.data, for: model.gameConfig.id)
            case .playAudio:
                await root.audioRoot.gameControllable.applyAudio(id: model.data.id, for: model.gameConfig.controls.map { $0.id } + [model.gameConfig.master.id])
                let _ = await root.audioRoot.gameControllable.play(with: model.data).result
            default:
                break
            }
        }
        return nil
    }

    func handleDice(_ model: GameNetworkModel) async throws -> GameNetworkModel? {
        let features = await root.gameModel.gameConfig.features
        guard await (root.gameModel.gameConfig.name != model.gameConfig.name) &&
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
                try await root.diceRoot.gameControllable.updateGame(data: model.data, hide: model.subType == .store, focus: model.subType == .show)
            case .generic:
                _ = await root.diceRoot.gameControllable.addGameDiceResult(data: model.data, name: model.gameConfig.name, isGameMaster: model.gameConfig.type == .master)
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
                if await gameModel.gameUpdateType == .photo {
                    await gameModel.setGameUpdateType(.none)
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
                    await root.mapRoot.gameControllable.updateMap(for: model.data.id, with: model.data)
                    let missingImages = await root.mapRoot.gameControllable.missingPlayerImages(itemId: model.data.id)
                    for idType in missingImages {
                        await send(counter: 0, type: .store, subType: .store, updated: idType)
                    }
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
                    root.photoRoot.gameControllable.resetPhotoSpace()
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
        guard await root.gameModel.gameConfig.type != .proxy else { return try await handleProxyValue(model) }
        guard model.gameConfig.type == .master else { return nil }
        switch model.type {
        case .reveal:
            if try await root.valueRoot.gameControllable.reveal(itemId: model.data.id, data: model.data, save: true) {
                Task { @MainActor in
                    gameModel.gameUpdateType = .value
                }
                return await response(for: model, isSuccess: true, requestData: false)
            } else {
                return await response(for: model, isSuccess: true, requestData: true)
            }
        case .store:
            try await root.valueRoot.gameControllable.updateGame(data: model.data, hide: model.subType == .store, deep: true)
            return await response(for: model, isSuccess: true, requestData: false)
        case .update:
            switch model.subType {
            case .generic:
                if let characterId = await root.gameModel.gameConfig.player.characterId {
                    Task { @MainActor in
                        await root.valueRoot.gameControllable.addItem(id: model.data.id, data: model.data, for: characterId)
                    }
                }
            case .valueResult:
                if let characterId = await root.gameModel.gameConfig.player.characterId {
                    Task { @MainActor in
                        await root.valueRoot.gameControllable.add(result: model.data, for: characterId)
                    }
                }
            default:
                Task { @MainActor in
                    if await root.valueRoot.gameControllable.setCurrent(itemId: model.data.id) {
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
                }
                return await response(for: model, isSuccess: true, requestData: false)
            } else {
                return await response(for: model, isSuccess: true, requestData: true)
            }
        case .store:
            try await root.spaceRoot.gameControllable.updateGame(data: model.data, hide: model.subType == .store, deep: true)
            return await response(for: model, isSuccess: true, requestData: false)
        case .update:
            Task { @MainActor in
                if await root.spaceRoot.gameControllable.setCurrent(itemId: model.data.id) {
                    gameModel.gameUpdateType = .space
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
            try await root.valueRoot.gameControllable.updateGame(data: model.data, hide: false, deep: true)
            let characterId = model.data.id
            Task { @MainActor in
                _ = await root.valueRoot.gameControllable.setCurrent(itemId: characterId)
                await root.valueRoot.gameControllable.focus(on: characterId)
                try await Task.sleep(for: .seconds(1))
                root.gameModel.selectedCharacter = characterId
            }
            return nil
        }
    }
    
    @MainActor func response(for model: GameNetworkModel, isSuccess: Bool, requestData: Bool) -> GameNetworkModel {
        if requestData {
            return GameNetworkModel(counter: model.counter, proxyCounter: model.proxyCounter, type: model.type, subType: model.subType, gameConfig: root.gameModel.gameConfig, data: model.data)
        }
        return GameNetworkModel(counter: model.counter, proxyCounter: model.proxyCounter, type: model.type, subType: isSuccess ? .ok : .failed, gameConfig: root.gameModel.gameConfig, data: NetworkCodableDataType(id: model.data.id, type: model.data.type, version: 0, data: nil))
    }
    
    func sendCharacter() async {
        let gameType = await root.gameModel.gameConfig.type
        guard await !gameModel.hasSendPlayer && gameType != .observer, let characterId = await root.gameModel.gameConfig.player.characterId else { return }
        await gameModel.reset(sendPlayer: true)

        if let result = try? await root.valueRoot.gameControllable.createGameData(for: characterId) {
            await send(counter: 0, type: .update, subType: .store, updated: result, useJournal: true)
        }
        try? await Task.sleep(for: .seconds(5))
        await sendAudioList()
    }

    func sendAudioList() async {
        await send(counter: 0, type: .update, subType: .audioList, updated: root.audioRoot.gameControllable.audioList(allPlayers: false, with: root.gameModel.gameConfig.id), useJournal: false)
    }
}
