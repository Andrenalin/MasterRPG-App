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
    var sendCharacterTask: Task<Void, Never>?
    var proxyFocusTask: Task<Void, Never>?
    // Map ids with an in-flight full-map re-request, so a burst of mapState
    // messages cannot trigger a request storm. Cleared when map data arrives.
    var pendingMapRequests: Set<UUID> = []
    // Photo ids already requested for repair. An id is only released when the
    // repair actually produced a local file — a permanently failing photo is
    // requested once instead of looping master responses forever.
    var requestedRepairIds: Set<UUID> = []

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

final class PlayerController: Sendable {
    // Strong on purpose: an intentional, temporary cycle GameRoot → GameModel →
    // PlayerController → GameRoot that stopGame() breaks by dropping the controllers.
    // `unowned` crashed here: delayed tasks (e.g. sendCharacter's 5s sleep) can
    // outlive stopGame()/teardown and would read a destroyed GameRoot. A strong
    // reference keeps GameRoot alive until the last in-flight task finishes.
    let root: GameRoot
    let gameModel: PlayerControllerModel
    let proxyMasterController: MasterController?
    let messagePipeline = GameMessagePipeline()
    
    @MainActor
    init(root: GameRoot, asGameMaster: Bool) {
        self.root = root
        self.gameModel = PlayerControllerModel()
        self.gameModel.asGameMaster = asGameMaster
        
        if asGameMaster {
            proxyMasterController = nil
            root.networkStore.setupLocal()
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
        await messagePipeline.cancelAll()
        gameModel.sendCharacterTask?.cancel()
        gameModel.sendCharacterTask = nil
        gameModel.proxyFocusTask?.cancel()
        gameModel.proxyFocusTask = nil
        await root.networkProxyStore.stopGame()
        await root.networkStore.stopGame()
        await root.adventureRoot.adventureGameControllable.resetGame()
        gameModel.hasSendPlayer = false
        gameModel.pendingMapRequests = []
        gameModel.requestedRepairIds = []
    }
    
    @MainActor
    func resetPlayers() {
        let players = root.gameModel.gameControl.controls.compactMap { $0.show ? $0.id : nil }
        root.audioRoot.gameControllable.gameModel.currentPlayers = (players + [root.gameModel.gameConfig.master.id]).sorted()
        let playerNames = root.gameModel.gameControl.controls.map { $0.name }.sorted()
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
        let networtData = await MainActor.run {
            root.gameModel.outgoingMessage(counter: counter, type: type, subType: subType, asMaster: false, data: updated)
        }

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
        await MainActor.run {
            gameModel.sendCharacterTask?.cancel()
            gameModel.sendCharacterTask = nil
            gameModel.pendingMapRequests = []
            gameModel.requestedRepairIds = []
        }
        await gameModel.reset(lostMaster: true)
        await gameModel.reset(sendPlayer: false)
    }
    
    func ready() async {
        Logger.networking.debug("PlayerController: Ready")
        await gameModel.reset(lostMaster: false)
        await scheduleSendCharacter()
    }
    
    func receivedFile(_ model: GameNetworkModel) async {
        Logger.networking.debug("PlayerController: FILE Received \(model.counter, privacy: .public): \(model.type.debugDescription, privacy: .public) - \(model.subType.debugDescription, privacy: .public), \(model.data.type.token, privacy: .public) id: \(model.data.id, privacy: .public)")
        guard await root.gameModel.gameConfig.isMaster != model.sender.isMaster else { return }
        await received(model)
    }
    
    func received(_ model: GameNetworkModel) async {
        await receivedProcess(model, fromProxy: false)
    }
    
    func receivedProcess(_ model: GameNetworkModel, fromProxy: Bool = false) async {
        Logger.networking.debug("PlayerController: Received \(model.counter, privacy: .public): \(model.type.debugDescription, privacy: .public) - \(model.subType.debugDescription, privacy: .public), \(model.data.type.token, privacy: .public) id: \(model.data.id, privacy: .public)")

        let origin: GameMessageOrigin = fromProxy ? .proxy : .direct(nil)
        guard await messagePipeline.enqueue(GameMessageEvent(model: model, origin: origin)) else {
            Logger.networking.debug("PlayerController: Duplicate ignored \(model.counter, privacy: .public): \(model.type.debugDescription, privacy: .public) - \(model.subType.debugDescription, privacy: .public), \(model.data.type.token, privacy: .public)")
            return
        }
        await processMessages()
    }

    private func prepareForProcessing(_ event: GameMessageEvent) async -> Bool {
        let model = event.model

        // Targeted messages are only processed by the addressee — including the
        // master's own local player. A message addressed to someone else is
        // still forwarded to local proxy clients: the addressee may sit behind
        // this player's proxy server.
        if let targetId = model.targetId, await targetId != root.gameModel.gameConfig.id {
            if !event.fromProxy {
                await root.networkProxyStore.sendPlayer(data: model)
            }
            Logger.networking.debug("PlayerController: Message ignored, targeted at \(targetId, privacy: .public)")
            return false
        }

        if await !gameModel.asGameMaster {
            let controls = model.masterState?.controls ?? []
            if let masterState = model.masterState, model.sender.isMaster {
                // One MainActor hop for the whole broadcast: applying config,
                // controls and roster in separate steps lets concurrent message
                // builders capture a torn state and send it back to the master.
                await MainActor.run {
                    root.gameModel.applyMasterBroadcast(masterId: model.masterId, masterName: model.sender.name, state: masterState)
                    resetPlayers()
                }
            }

            let localId = await root.gameModel.gameConfig.id
            let type = await root.gameModel.gameType
            guard type == .proxy || type == .observer || controls.isEmpty || controls.contains(where: { $0.id == localId && $0.show == true }) else {
                Logger.networking.debug("PlayerController: Message will be ignored because of controls \(controls, privacy: .public)")
                return false
            }
            guard await root.gameModel.gameType == .proxy || model.sender.isMaster || model.data.type == .dice || model.subType == .spaceTransform else {
                Logger.networking.debug("PlayerController: Message will be ignored because it is send from Player \(model.senderName, privacy: .public)")
                return false
            }
        }

        if !event.fromProxy {
            await root.networkProxyStore.sendPlayer(data: model)
            await scheduleSendCharacter()
        }
        return true
    }
    
    func processMessages() async {
        while let event = await messagePipeline.next() {
            guard await prepareForProcessing(event) else {
                await messagePipeline.processed()
                continue
            }

            let response = try? await handle(event.model)
            if let response {
                await send(model: response)
                if response.subType == .ok {
                    await gameModel.increaseMessageCounter()
                }
            } else {
                await gameModel.increaseMessageCounter()
            }
            await messagePipeline.processed()
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
            await root.audioRoot.gameControllable.report(itemId: model.data.id, for: model.sender.id)
            return nil
        }
        
        switch model.type {
        case .reveal:
            if try await root.audioRoot.gameControllable.reveal(itemId: model.data.id, data: model.data, save: true) {
                await root.audioRoot.audioGameControllable.applyAudio(id: model.data.id, for: [root.gameModel.gameConfig.id, model.sender.id])
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
                await root.audioRoot.audioGameControllable.applyAudioList(data: model.data, for: model.sender.id)
            case .playAudio:
                await root.audioRoot.audioGameControllable.applyAudio(id: model.data.id, for: (model.masterState?.controls.map { $0.id } ?? []) + [model.masterId])
                let isSharePlayActive = await MainActor.run { root.networkStore.sharePlayStore.isActive }
                if isSharePlayActive && !model.sender.isMaster {
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
        let features = await root.gameModel.gameControl.features
        guard await (root.gameModel.gameName != model.senderName) &&
                (features.diceMaster || !model.sender.isMaster) &&
                (features.dicePlayers || model.sender.isMaster)
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
                _ = await root.diceRoot.diceGameControllable.addGameDiceResult(data: model.data, name: model.senderName, isGameMaster: model.sender.isMaster)
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
            await MainActor.run { _ = gameModel.pendingMapRequests.remove(model.data.id) }
            if try await root.mapRoot.gameControllable.reveal(itemId: model.data.id, data: model.data, save: false) {
                _ = await root.mapRoot.gameControllable.setCurrent(itemId: model.data.id)
                await MainActor.run {
                    // Also for players: a reveal means "show the map". Waiting for
                    // the next mapState left the screen behind the black overlay
                    // when that one-shot message was missed.
                    gameModel.gameUpdateType = .map
                }
                await requestMissingMapImages(itemId: model.data.id)
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
            await MainActor.run { _ = gameModel.pendingMapRequests.remove(model.data.id) }
            try await root.mapRoot.gameControllable.updateGame(data: model.data, hide: true, deep: true)
            return await response(for: model, isSuccess: true, requestData: false)
        case .update:
            switch model.subType {
            case .mapState:
                if await root.mapRoot.gameControllable.hasItem(id: model.data.id, version: model.data.version) {
                    await root.mapRoot.mapGameControllable.updateMap(for: model.data.id, with: model.data)
                    await requestMissingMapImages(itemId: model.data.id)

                    // Update fog of war on 3D board
                    #if os(visionOS)
                    let isGameMaster = await root.gameModel.gameConfig.isMaster
                    await root.gameModel.gameTableModel?.updateFogOfWar(isGameMaster: isGameMaster)
                    await MainActor.run {
                        root.gameModel.gameTableModel?.syncPawnsWithMapPins()
                    }
                    #endif
                } else {
                    // Re-request the full map once — the master answers a
                    // `.reveal .mapState` with the map data plus the current map
                    // state. A plain `.ok` is only an ACK and would dead-end here.
                    let isFirstRequest = await MainActor.run { gameModel.pendingMapRequests.insert(model.data.id).inserted }
                    return await MainActor.run {
                        root.gameModel.outgoingMessage(counter: model.counter, proxyCounter: model.proxyCounter, type: .reveal, subType: isFirstRequest ? .mapState : .ok, asMaster: false, data: NetworkCodableDataType(id: model.data.id, type: model.data.type, version: 0, data: nil))
                    }
                }
            case .mapPin:
                // master will never send mapPin updates, they come only from players.
                break
            default:
                break
            }
            await MainActor.run {
                gameModel.gameUpdateType = .map
            }
        }
        return nil
    }

    /// Requests photos the current map needs (background and player pins) whose
    /// binary is not available locally, via the unconditional `.store` path.
    /// Each photo is requested once per connection; the id is released when the
    /// repair delivers a local file, so a failing photo cannot loop.
    func requestMissingMapImages(itemId: UUID) async {
        let missingImages = await root.mapRoot.mapGameControllable.missingPlayerImages(itemId: itemId)
        for idType in missingImages {
            let isFirstRequest = await MainActor.run { gameModel.requestedRepairIds.insert(idType.id).inserted }
            guard isFirstRequest else { continue }
            await send(counter: 0, type: .store, subType: .store, updated: idType)
        }
    }

    func handlePdf(_ model: GameNetworkModel) async throws -> GameNetworkModel? {
        switch model.type {
            case .reveal:
                if try await root.pdfRoot.gameControllable.reveal(itemId: model.data.id, data: model.data, save: true) {
                    await MainActor.run {
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
                await MainActor.run {
                    gameModel.gameUpdateType = .photo
                    root.photoRoot.photoGameControllable.resetPhotoSpace()
                }
                
                return await response(for: model, isSuccess: true, requestData: false)
            } else {
                return await response(for: model, isSuccess: true, requestData: true)
            }
        case .store:
            try await root.photoRoot.gameControllable.updateGame(data: model.data, hide: model.subType == .store, deep: true)
            if await root.photoRoot.gameControllable.hasLocalFileData(for: model.data.id) {
                await MainActor.run { _ = gameModel.requestedRepairIds.remove(model.data.id) }
            }
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
            if await root.photoRoot.gameControllable.setCurrent(itemId: model.data.id) {
                await MainActor.run {
                    gameModel.gameUpdateType = .photo
                }
            }
        }
        return nil
    }
    
    func handleTable(_ model: GameNetworkModel) async throws -> GameNetworkModel? {
        switch model.type {
        case .reveal:
            if try await root.tableRoot.gameControllable.reveal(itemId: model.data.id, data: model.data, save: true) {
                await MainActor.run {
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
        guard model.sender.isMaster else { return nil }
        switch model.type {
        case .reveal:
            if try await root.characterRoot.gameControllable.reveal(itemId: model.data.id, data: model.data, save: true) {
                await MainActor.run {
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
                    await root.characterRoot.valueGameControllable.addItem(id: model.data.id, data: model.data, for: characterId)
                }
            case .valueResult:
                if let characterId = await root.gameModel.gamePlayer.characterId {
                    await root.characterRoot.valueGameControllable.add(result: model.data, for: characterId)
                }
            default:
                if await root.characterRoot.gameControllable.setCurrent(itemId: model.data.id) {
                    await MainActor.run {
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
                await MainActor.run {
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
            if await root.weatherRoot.gameControllable.setCurrent(itemId: model.data.id) {
                await MainActor.run {
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
                await MainActor.run {
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
            if await root.spaceRoot.gameControllable.setCurrent(itemId: model.data.id) {
                await MainActor.run {
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
            await scheduleProxyFocus(characterId: characterId)
            return nil
        }
    }
    
    nonisolated func response(for model: GameNetworkModel, isSuccess: Bool, requestData: Bool) async -> GameNetworkModel {
        let subType: RPGMessageActionType = requestData ? model.subType : (isSuccess ? .ok : .failed)
        let payload = requestData ? model.data : NetworkCodableDataType(id: model.data.id, type: model.data.type, version: 0, data: nil)
        return await MainActor.run {
            root.gameModel.outgoingMessage(counter: model.counter, proxyCounter: model.proxyCounter, type: model.type, subType: subType, asMaster: false, data: payload)
        }
    }

    func scheduleSendCharacter() async {
        await MainActor.run {
            guard gameModel.sendCharacterTask == nil else { return }
            gameModel.sendCharacterTask = Task { [weak self] in
                await self?.sendCharacter()
                await MainActor.run {
                    self?.gameModel.sendCharacterTask = nil
                }
            }
        }
    }

    func scheduleProxyFocus(characterId: UUID) async {
        await MainActor.run {
            gameModel.proxyFocusTask?.cancel()
            gameModel.proxyFocusTask = Task { [weak self] in
                guard let self else { return }
                _ = await root.characterRoot.gameControllable.setCurrent(itemId: characterId)
                await root.characterRoot.gameControllable.focus(on: characterId)
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    await MainActor.run {
                        self.gameModel.proxyFocusTask = nil
                    }
                    return
                }
                guard !Task.isCancelled else {
                    await MainActor.run {
                        self.gameModel.proxyFocusTask = nil
                    }
                    return
                }
                await MainActor.run {
                    root.gameModel.selectedCharacter = characterId
                    gameModel.proxyFocusTask = nil
                }
            }
        }
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
        guard !Task.isCancelled else { return }
        await sendAudioList()
    }

    func sendAudioList() async {
        await send(counter: 0, type: .update, subType: .audioList, updated: root.audioRoot.audioGameControllable.audioList(allPlayers: false, with: root.gameModel.gameConfig.id), useJournal: false)
    }
}
