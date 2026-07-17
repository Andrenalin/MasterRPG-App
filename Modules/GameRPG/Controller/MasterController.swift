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
    var messageCounter: Int = 1
    var connectIDPlayers: [ConnectionController.ID: UUID] = [:]
    var asProxy = false
    var pendingAudioPlays: [UUID: NetworkCodableDataType] = [:]
    var audioTransferPlayers: [UUID: Set<UUID>] = [:]
    private var lastAudioListCounters: [UUID: Int] = [:]
    /// Latest file-backed item versions whose full package already went out in
    /// the current game. A changed version must be broadcast in full again;
    /// otherwise a new map is reduced to a reference and unnecessarily falls
    /// back to a requester-only SharePlay chunk transfer.
    var sentGameItems: [NetworkModules: [UUID: Int]] = [:]

    func hasSentGameItem(type: NetworkModules, id: UUID, version: Int) -> Bool {
        sentGameItems[type]?[id] == version
    }

    func markSentGameItem(type: NetworkModules, id: UUID, version: Int) {
        sentGameItems[type, default: [:]][id] = version
    }
    
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

    func remove(connectionId: ConnectionController.ID) -> UUID? {
        guard let playerId = connectIDPlayers.removeValue(forKey: connectionId) else { return nil }
        lastAudioListCounters[playerId] = nil
        return playerId
    }

    func canApplyAudioList(from playerId: UUID, counter: Int) -> Bool {
        guard counter >= 0 else { return false }
        guard counter > 0 else { return true }
        return counter > (lastAudioListCounters[playerId] ?? 0)
    }

    func recordAudioList(counter: Int, from playerId: UUID) {
        guard counter > 0 else { return }
        lastAudioListCounters[playerId] = counter
    }

    func resetAudioListSequence() {
        lastAudioListCounters.removeAll()
    }
}

final class MasterController: Sendable {
    // Strong on purpose: an intentional, temporary cycle GameRoot → GameModel →
    // MasterController → GameRoot that stopGame() breaks by dropping the controllers.
    // `unowned` crashed here when in-flight controller tasks outlived
    // stopGame()/teardown. A strong reference keeps GameRoot alive until the
    // last task finishes.
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
        gameModel.pendingAudioPlays.removeAll()
        gameModel.audioTransferPlayers.removeAll()
        gameModel.sentGameItems.removeAll()
        gameModel.resetAudioListSequence()
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

        let previousAudioPlayers = Set(await root.audioRoot.gameControllable.gameModel.currentPlayers)
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
            #if !os(tvOS)
            await MainActor.run {
                root.gameModel.gameTableModel?.syncPawnsWithMapPins()
            }
            #endif
            // Push the changed player pins to everyone right away — otherwise
            // a joining player's pin only appears on the next unrelated map
            // state update.
            if let mapId = await root.mapRoot.gameControllable.gameModel.currentItemId {
                // Messenger messages have no history. Replay the latest
                // photo-free structural snapshot when the roster changes so a
                // SharePlay participant joining after the Journal publication
                // receives edits made since that base attachment.
                await send(
                    type: .update,
                    subtype: .generic,
                    updated: await root.mapRoot.mapGameControllable.networkMapContentUpdate(for: mapId)
                )
                await send(type: .update, subtype: .mapState, updated: root.mapRoot.mapGameControllable.networkMapUpdate(for: mapId))
            }
        }
        // A newly joined player reports its database-backed audio list from
        // ready(). Wait for that report before deciding whether to transfer.
        // Removals can immediately unblock a pending play.
        if Set(players).isSubset(of: previousAudioPlayers) {
            await continuePendingAudioPlays()
        }
    }
}

// MARK: - Send Messages

extension MasterController {
    func show(for idType: NetworkCodableDataType) async {
        // Map call sites from older modules/tests still construct the legacy
        // scale-only reference. Resolve the current background/content
        // fingerprints here so the Journal cache never falls back to that
        // mutable version.
        let resolvedIdType: NetworkCodableDataType
        if idType.type == .map, idType.assetVersion == nil {
            resolvedIdType = await root.mapRoot.mapGameControllable.shareMap(id: idType.id)
        } else {
            resolvedIdType = idType
        }
        // File-backed payloads are big (a map package carries background + pin +
        // player photos). The first show of each version ships the whole payload
        // right away — the id-then-request round trip would make every player wait
        // one extra full transfer, and over SharePlay the broadcast rides the
        // journal as one shared attachment. A same-version reshow sends only the
        // reference; players still holding the item show it from memory, the
        // others request it.
        if Self.sendsFullPayloadOnFirstShow(resolvedIdType.type), await !gameModel.hasSentGameItem(type: resolvedIdType.type, id: resolvedIdType.id, version: resolvedIdType.effectiveAssetVersion) {
            if let fullData = try? await createGameData(for: resolvedIdType) {
                await MainActor.run {
                    gameModel.markSentGameItem(type: fullData.type, id: fullData.id, version: fullData.effectiveAssetVersion)
                }
                await send(type: .reveal, subtype: .show, updated: fullData)
                return
            }
            Logger.networking.error("MasterController: Cannot create package for \(resolvedIdType.type.token, privacy: .public) \(resolvedIdType.id, privacy: .public) — sending reference instead")
        }
        await send(type: .reveal, subtype: .show, updated: resolvedIdType)
    }

    static func sendsFullPayloadOnFirstShow(_ type: NetworkModules) -> Bool {
        switch type {
        case .map, .photo, .pdf, .space:
            true
        default:
            false
        }
    }

    private func createGameData(for idType: NetworkCodableDataType) async throws -> NetworkCodableDataType? {
        switch idType.type {
        case .map:
            try await root.mapRoot.mapGameControllable.createMapGameData(for: idType.id)
        case .photo:
            try await root.photoRoot.gameControllable.createGameData(for: idType.id)
        case .pdf:
            try await root.pdfRoot.gameControllable.createGameData(for: idType.id)
        case .space:
            try await root.spaceRoot.gameControllable.createGameData(for: idType.id)
        default:
            nil
        }
    }
    
    func game(message: NetworkCodableDataType, actionType: RPGMessageActionType, playerId: UUID? = nil) async {
        if message.type == .audio, actionType == .playAudio {
            await requestAudioPlay(message)
            return
        }
        await send(type: .update, subtype: actionType, updated: message, playerId: playerId)
    }
    
    func send(updated: NetworkCodableDataType) async {
        await send(type: .store, subtype: .store, updated: updated)
    }
    
    func send(type: RPGMessageType, subtype: RPGMessageActionType, updated: NetworkCodableDataType, connectionId: ConnectionController.ID? = nil, playerId: UUID? = nil, authoritativeMaster: Bool? = nil) async {
        let counter = await gameModel.nextMessageCounter()
        Logger.networking.debug("MasterController: Send \(counter, privacy: .public): \(type.debugDescription, privacy: .public) - \(subtype.debugDescription, privacy: .public) for \(updated.type.token, privacy: .public) -> \(updated.id, privacy: .public)")

        // Built from local state in one MainActor hop; a playerId becomes the
        // message target so only the addressee processes it.
        let networtData = await MainActor.run {
            root.gameModel.outgoingMessage(counter: counter, type: type, subType: subtype, asMaster: authoritativeMaster ?? !asProxy, targetId: playerId, data: updated)
        }

        await root.logGameController.addMessage(counter: counter, type: type, subType: subtype, module: updated.type, itemId: updated.id)
        await root.statisticsModel.record(
            networtData,
            direction: .outgoing,
            origin: asProxy ? .proxy : .direct(connectionId)
        )

        if asProxy {
            if let connectionId {
                await root.networkProxyStore.sendPlayer(networtData, to: connectionId)
            } else {
                await root.networkProxyStore.sendPlayer(data: networtData)
            }
        } else if let connectionId {
            await root.networkStore.sendPlayer(networtData, to: connectionId)
        } else {
            await root.networkStore.sendPlayer(data: networtData, fileJournal: Self.usesFileJournal(for: networtData))
        }
    }

    static func usesFileJournal(for model: GameNetworkModel) -> Bool {
        model.usesFileJournal
    }

    static func usesFileJournal(for data: NetworkCodableDataType) -> Bool {
        data.usesFileJournal
    }
}

// MARK: - MasterNetworkStoreDelegate

extension MasterController: MasterNetworkStoreDelegate {
    func ready(for connectionId: ConnectionController.ID) async {
        Logger.networking.debug("MasterController: Ready for \(connectionId, privacy: .public)")
        await replayCurrentPresentation(to: connectionId)
    }
    
    func lostPlayer(for connectionId: ConnectionController.ID) async {
        Logger.networking.debug("MasterController: Lost Player for \(connectionId, privacy: .public)")
        guard let playerId = await gameModel.remove(connectionId: connectionId) else { return }
        await root.audioRoot.gameControllable.gameModel.removePlayerReport(for: playerId)
        if await root.gameModel.remove(playerId: playerId) {
            await root.statisticsModel.participantLeft(id: playerId)
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
            let success = await process(event)
            await messagePipeline.processed(success: success)
        }
    }

    private func process(_ event: GameMessageEvent) async -> Bool {
        let model = event.model

        await root.logGameController.updateMessage(counter: model.counter, player: model.sender.id)
        if let connectionId = event.connectionId {
            await gameModel.add(connectionId: connectionId, playerId: model.sender.id)
        }

        // Before the roster add: a proxy client is a private mirror of the host
        // player and must never appear as a player of its own — not in the
        // host's roster and never upstream at the master.
        if asProxy {
            let success = await processAsProxy(model)
            if success {
                await root.statisticsModel.record(model, direction: .incoming, origin: event.origin)
            }
            return success
        }

        if !model.sender.isMaster, model.sender.role != .notSet {
            if await root.gameModel.add(playerId: model.sender.id, playerModel: model.sender.playerModel, sharingModel: SharingControlModel(id: model.sender.id, name: model.sender.name, show: true)) {
                await resetPlayers()
            }
        }

        do {
            try Task.checkCancellation()
            if let requestedData = try await handle(model) {
                try Task.checkCancellation()
                if requestedData.data != nil {
                    // The full payload went out — a later reshow can rely on
                    // the reference no matter which path delivered first.
                    await gameModel.markSentGameItem(type: requestedData.type, id: requestedData.id, version: requestedData.effectiveAssetVersion)
                }
                // Target the answer at the requester: an untargeted full payload
                // re-triggered "show" on every peer and flipped everyone's screen.
                // When the request came over a direct connection, answer on that
                // connection only — broadcasting a targeted multi-MB payload made
                // every transfer ride the SharePlay messenger once per requester.
                // A proxied client behind the connection still gets it: its host
                // forwards messages targeted at someone else to its proxy clients.
                await send(type: model.type, subtype: model.subType, updated: requestedData, connectionId: event.connectionId, playerId: model.sender.id)
            }
            await root.statisticsModel.record(model, direction: .incoming, origin: event.origin)
            return true
        } catch is CancellationError {
            return false
        } catch {
            Logger.networking.error("MasterController: Failed to process \(model.debugDescription, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
    
    func receivedFile(_ model: GameNetworkModel) async {
        Logger.networking.debug("MasterController: FILE Received \(model.counter, privacy: .public): \(model.type.debugDescription, privacy: .public) - \(model.subType.debugDescription, privacy: .public), \(model.data.type.token, privacy: .public) id: \(model.data.id, privacy: .public)")
        guard await root.gameModel.gameConfig.isMaster != model.sender.isMaster else { return }
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
        if model.subType == .ok {
            await root.audioRoot.gameControllable.report(itemId: model.data.id, for: model.sender.id)
            await continuePendingAudioPlays()
            return nil
        }
        if model.subType == .failed {
            await audioTransferFailed(itemId: model.data.id, playerId: model.sender.id)
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
                await requestAudioPlay(model.data)
            case .audioList:
                guard await applyAudioList(model) else { return nil }
                await resetAudioTransfers(for: model.sender.id)
                let audioList = await root.audioRoot.audioGameControllable.audioList(allPlayers: true, with: root.gameModel.gameConfig.id)
                await send(type: .update, subtype: .audioList, updated: audioList)
                await continuePendingAudioPlays()
            default:
                break
            }
            return nil
        }
    }

    @MainActor
    private func applyAudioList(_ model: GameNetworkModel) -> Bool {
        guard !model.sender.isMaster,
              gameModel.canApplyAudioList(from: model.sender.id, counter: model.counter),
              root.audioRoot.audioGameControllable.applyAudioList(
                  data: model.data,
                  for: model.sender.id,
                  authoritative: false
              )
        else { return false }

        gameModel.recordAudioList(counter: model.counter, from: model.sender.id)
        return true
    }

    @MainActor
    func requestAudioPlay(_ data: NetworkCodableDataType) async {
        if !root.audioRoot.audioGameControllable.shouldPlay(with: data) {
            gameModel.pendingAudioPlays[data.id] = nil
            gameModel.audioTransferPlayers[data.id] = nil
            await broadcastAudioPlay(data)
            return
        }

        gameModel.pendingAudioPlays[data.id] = data
        await fulfillPendingAudioPlay(id: data.id, data: data)
    }

    @MainActor
    private func continuePendingAudioPlays() async {
        let pending = gameModel.pendingAudioPlays
        for (id, data) in pending {
            await fulfillPendingAudioPlay(id: id, data: data)
        }
    }

    @MainActor
    private func fulfillPendingAudioPlay(id: UUID, data: NetworkCodableDataType) async {
        let missingPlayers = Set(root.audioRoot.audioGameControllable.missingPlayers(for: id))
        if missingPlayers.isEmpty {
            gameModel.pendingAudioPlays[id] = nil
            gameModel.audioTransferPlayers[id] = nil
            await broadcastAudioPlay(data)
            return
        }

        let inFlight = gameModel.audioTransferPlayers[id] ?? []
        let newPlayers = missingPlayers.subtracting(inFlight)
        guard !newPlayers.isEmpty else { return }

        do {
            gameModel.audioTransferPlayers[id] = inFlight.union(newPlayers)
            let audioData = try await root.audioRoot.gameControllable.createGameData(for: id)
            guard gameModel.pendingAudioPlays[id] != nil else {
                gameModel.audioTransferPlayers[id] = nil
                return
            }
            let stillMissing = Set(root.audioRoot.audioGameControllable.missingPlayers(for: id))
                .intersection(newPlayers)
            for playerId in stillMissing.sorted() {
                await send(type: .store, subtype: .show, updated: audioData, playerId: playerId)
            }
        } catch {
            gameModel.audioTransferPlayers[id]?.subtract(newPlayers)
            Logger.networking.error("MasterController: Cannot prepare pending audio \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    @MainActor
    private func audioTransferFailed(itemId: UUID, playerId: UUID) {
        gameModel.audioTransferPlayers[itemId]?.remove(playerId)
    }

    @MainActor
    private func resetAudioTransfers(for playerId: UUID) {
        for itemId in gameModel.audioTransferPlayers.keys {
            gameModel.audioTransferPlayers[itemId]?.remove(playerId)
        }
    }

    @MainActor
    private func broadcastAudioPlay(_ data: NetworkCodableDataType) async {
        await send(type: .update, subtype: .playAudio, updated: data)
        let hasLocalPlayer = root.networkStore.model.hasLocalPlayer
        if !hasLocalPlayer {
            let _ = await root.audioRoot.audioGameControllable.play(with: data).result
        }
    }
    
    func handleDice(_ model: GameNetworkModel) async throws -> NetworkCodableDataType? {
        guard model.subType != .ok && model.subType != .failed && model.senderType != .observer else { return nil }

        switch model.type {
        case .reveal, .store:
            return try await root.diceRoot.gameControllable.createGameData(for: model.data.id)
        case .update:
            let (diceResult, resultCategory) = await root.diceRoot.diceGameControllable.addGameDiceResult(data: model.data, name: model.senderName, isGameMaster: model.sender.isMaster)
            if let diceResult, let resultCategory {
                await root.tableRoot.tableGameControllable.addResult(resultCategory, value: diceResult)
            }
        }
        return nil
    }
    
    func handleGame(_ model: GameNetworkModel) async throws -> NetworkCodableDataType? {
        await root.logGameController.updateScreen(counter: model.counter, player: model.sender.id, data: model.data.data)
        return nil
    }
    
    func handleMap(_ model: GameNetworkModel) async throws -> NetworkCodableDataType? {
        if model.subType == .ok {
            await root.mapRoot.gameControllable.report(itemId: model.data.id, for: model.sender.id)
            return nil
        }
        guard model.subType != .failed else { return nil }
        
        switch model.type {
        case .reveal:
            let mapData = try await root.mapRoot.mapGameControllable.createMapGameData(for: model.data.id)
            // The full package went out through the request path — reshows can
            // rely on the reference no matter which path delivered first.
            await MainActor.run {
                gameModel.markSentGameItem(type: .map, id: mapData.id, version: mapData.effectiveAssetVersion)
            }
            if model.subType == .mapState {
                // Targeted at the recovering player: everyone else already has
                // the map, and over SharePlay an untargeted full payload would
                // be skipped as identical to the published journal attachment.
                await send(type: .reveal, subtype: .store, updated: mapData, playerId: model.sender.id)
                // Send the live map state (not the request echo, whose data is
                // nil) so the recovering player syncs room visibility and pins.
                // Targeted: the other players are already up to date.
                await send(
                    type: .update,
                    subtype: .generic,
                    updated: await root.mapRoot.mapGameControllable.networkMapContentUpdate(for: model.data.id),
                    playerId: model.sender.id
                )
                await send(type: .update, subtype: .mapState, updated: root.mapRoot.mapGameControllable.networkMapUpdate(for: model.data.id), playerId: model.sender.id)
            } else {
                return mapData
            }
        case .store:
            break
        case .update:
            guard model.senderType != .observer else { return nil }
            switch model.subType {
            case .generic:
                // A data-less generic map update is a repair request for the
                // latest photo-free structural snapshot. The normal response
                // path targets the small chunked answer at the requester.
                guard model.data.data == nil else { return nil }
                return await root.mapRoot.mapGameControllable.networkMapContentUpdate(for: model.data.id)
            case .mapState:
                // never get from players mapState updates, only as resend from SharePlay?
                break
            case .mapPin:
                if await root.mapRoot.mapGameControllable.updatePin(
                    itemId: model.data.id,
                    data: model.data.data,
                    playerId: model.sender.id
                ) {
                    #if !os(tvOS)
                    await MainActor.run {
                        root.gameModel.gameTableModel?.syncPawnsWithMapPins()
                    }
                    #endif
                    await send(type: .update, subtype: .mapState, updated: root.mapRoot.mapGameControllable.networkMapUpdate(for: model.data.id))
                }
            default:
                break
            }
        }
        return nil
    }

    func handlePdf(_ model: GameNetworkModel) async throws -> NetworkCodableDataType? {
        if model.subType == .ok {
            await root.pdfRoot.gameControllable.report(itemId: model.data.id, for: model.sender.id)
            return nil
        }
        guard model.subType != .failed else { return nil }

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
        if model.subType == .ok {
            await root.photoRoot.gameControllable.report(itemId: model.data.id, for: model.sender.id)
            return nil
        }
        guard model.subType != .failed else { return nil }
        
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
        if model.subType == .ok {
            await root.tableRoot.gameControllable.report(itemId: model.data.id, for: model.sender.id)
            return nil
        }
        guard model.subType != .failed else { return nil }
        
        switch model.type {
        case .reveal, .store:
            return try await root.tableRoot.gameControllable.createGameData(for: model.data.id)
        case .update:
            break
        }
        return nil
    }

    func handleValue(_ model: GameNetworkModel) async throws -> NetworkCodableDataType? {
        if model.subType == .ok {
            await root.characterRoot.gameControllable.report(itemId: model.data.id, for: model.sender.id)
            return nil
        }
        guard model.subType != .failed else { return nil }

        switch model.type {
        case .reveal, .store:
            return try await root.characterRoot.gameControllable.createGameData(for: model.data.id)
        case .update:
            guard model.senderType != .observer else { return nil }
            try await root.characterRoot.valueGameControllable.updatePlayer(data: model.data)
            if let characterId = model.sender.characterId {
                await root.mapRoot.mapGameControllable.setPlayerPin(for: model.sender.id, name: model.senderName, characterId: characterId)
            }
        }
        return nil
    }
    
    func handleWeather(_ model: GameNetworkModel) async throws -> NetworkCodableDataType? {
        if model.subType == .ok {
            await root.weatherRoot.gameControllable.report(itemId: model.data.id, for: model.sender.id)
            return nil
        }
        guard model.subType != .failed else { return nil }
        return try await root.weatherRoot.gameControllable.createGameData(for: model.data.id)
    }
    
    func handleSpace(_ model: GameNetworkModel) async throws -> NetworkCodableDataType? {
        if model.subType == .ok {
            await root.spaceRoot.gameControllable.report(itemId: model.data.id, for: model.sender.id)
            return nil
        }
        guard model.subType != .failed else { return nil }
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
        await replayCurrentPresentation(to: connectionId)
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

// MARK: - Proxy host routing

private extension MasterController {
    /// Routes a proxy client's message. The proxy device is a private mirror of
    /// the host player: nothing leaves this device with the proxy's identity,
    /// so the master and the other players never see it.
    func processAsProxy(_ model: GameNetworkModel) async -> Bool {
        // Reports and screens are meaningless upstream — the master does not
        // know the proxy exists. The host is authoritative for the character
        // and the audio availability, so the proxy's own announcements drop too.
        if model.isAcknowledgement || model.subType == .screen || model.subType == .audioList {
            return true
        }
        if model.data.type == .value, model.type == .update, model.subType == .store {
            return true
        }

        if model.data.type == .dice, model.type == .update {
            // The proxy rolls as the host player — show it on the host as well.
            let hostName = await root.gameModel.gamePlayer.name
            _ = await root.diceRoot.diceGameControllable.addGameDiceResult(data: model.data, name: hostName, isGameMaster: false)
            await remapUpstream(model)
            return true
        }

        if model.data.type == .map, model.type == .update, model.subType == .mapPin {
            // Update the host's own map first, then tell the master.
            let hostId = await root.gameModel.gameConfig.id
            guard await root.mapRoot.mapGameControllable.updatePin(
                itemId: model.data.id,
                data: model.data.data,
                playerId: hostId
            ) else {
                return true
            }
            await remapUpstream(model)
            return true
        }

        if model.data.type == .space, model.type == .update, model.subType == .spaceTransform {
            // Mirror the manipulation on the host; the master fan-out covers the rest.
            try? await root.spaceRoot.gameControllable.updateGame(data: model.data, subtype: .spaceTransform)
            await remapUpstream(model)
            return true
        }

        if model.data.data == nil, model.type == .reveal || model.type == .store {
            if await canServeProxyRequest(for: model.data) {
                do {
                    // Serve from the host's own game memory — local network is
                    // fast and the master never learns about the proxy.
                    // `authoritativeMaster` mirrors replayCurrentPresentation:
                    // the proxy's handlers only accept reveals from the master.
                    if let requestedData = try await handle(model) {
                        await send(type: model.type, subtype: model.subType, updated: requestedData, playerId: model.sender.id, authoritativeMaster: true)
                    }
                    return true
                } catch {
                    Logger.networking.error("MasterController: Cannot serve proxy request locally \(model.debugDescription, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
            // The host lacks the data itself — ask the master as the host. The
            // targeted answer is forwarded to the proxy with the target cleared.
            await remapUpstream(model)
            return true
        }

        await remapUpstream(model)
        return true
    }

    /// Re-sends a proxy client's message as the host player's own — fresh host
    /// counter, host sender identity, same payload.
    func remapUpstream(_ model: GameNetworkModel) async {
        guard let playerController = await root.gameModel.playerController else {
            Logger.networking.error("MasterController: No player controller to remap proxy message \(model.debugDescription, privacy: .public)")
            return
        }
        await playerController.send(type: model.type, subType: model.subType, updated: model.data)
    }

    /// Whether the host holds everything needed to answer a proxy data request
    /// itself, including the binaries of file-backed modules.
    func canServeProxyRequest(for data: NetworkCodableDataType) async -> Bool {
        switch data.type {
        case .photo:
            return await root.photoRoot.gameControllable.hasLocalFileData(for: data.id)
        case .pdf:
            return await root.pdfRoot.gameControllable.hasLocalFileData(for: data.id)
        case .audio:
            return await root.audioRoot.gameControllable.hasLocalFileData(for: data.id)
        case .space:
            return await root.spaceRoot.gameControllable.hasLocalFileData(for: data.id)
        case .map:
            guard await root.mapRoot.mapGameControllable.hasBackgroundImage(itemId: data.id) else { return false }
            return await root.mapRoot.mapGameControllable.missingMapImages(itemId: data.id).isEmpty
        default:
            return true
        }
    }
}

private extension MasterController {
    func replayCurrentPresentation(to connectionId: ConnectionController.ID) async {
        guard let presentation = await root.gameModel.playerController?.gameModel.gameUpdateType else { return }

        let reference: NetworkCodableDataType?
        switch presentation {
        case .map:
            reference = if let id = await root.mapRoot.gameControllable.gameModel.currentItemId {
                await root.mapRoot.mapGameControllable.shareMap(id: id)
            } else {
                nil
            }
        case .pdf:
            reference = if let id = await root.pdfRoot.gameControllable.gameModel.currentItemId {
                await root.pdfRoot.gameControllable.share(id: id)
            } else {
                nil
            }
        case .photo:
            reference = if let id = await root.photoRoot.gameControllable.gameModel.currentItemId {
                await root.photoRoot.gameControllable.share(id: id)
            } else {
                nil
            }
        case .table:
            reference = if let id = await root.tableRoot.gameControllable.gameModel.currentItemId {
                await root.tableRoot.gameControllable.share(id: id)
            } else {
                nil
            }
        case .value:
            reference = if let id = await root.characterRoot.gameControllable.gameModel.currentItemId {
                await root.characterRoot.gameControllable.share(id: id)
            } else {
                nil
            }
        case .weather:
            reference = if let id = await root.weatherRoot.gameControllable.gameModel.currentItemId {
                await root.weatherRoot.gameControllable.share(id: id)
            } else {
                nil
            }
        case .space:
            reference = if let id = await root.spaceRoot.gameControllable.gameModel.currentItemId {
                await root.spaceRoot.gameControllable.share(id: id)
            } else {
                nil
            }
        default:
            reference = nil
        }

        guard let reference else { return }
        await send(
            type: .reveal,
            subtype: .show,
            updated: reference,
            connectionId: connectionId,
            authoritativeMaster: true
        )
        if presentation == .map {
            let mapUpdate = await root.mapRoot.mapGameControllable.networkMapContentUpdate(for: reference.id)
            await send(
                type: .update,
                subtype: .generic,
                updated: mapUpdate,
                connectionId: connectionId,
                authoritativeMaster: true
            )
            let mapState = await root.mapRoot.mapGameControllable.networkMapUpdate(for: reference.id)
            await send(
                type: .update,
                subtype: .mapState,
                updated: mapState,
                connectionId: connectionId,
                authoritativeMaster: true
            )
        }
    }
}
