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
    private struct SpaceTransformSequenceKey: Hashable, Sendable {
        let playerId: UUID
        let itemId: UUID
        let version: Int
    }

    var messageCounter: Int = 1
    var connectIDPlayers: [ConnectionController.ID: UUID] = [:]
    var asProxy = false
    var pendingAudioPlays: [UUID: NetworkCodableDataType] = [:]
    var audioTransferPlayers: [UUID: Set<UUID>] = [:]
    private var lastAudioListCounters: [UUID: Int] = [:]
    private var lastPhotoListCounters: [UUID: Int] = [:]
    private var lastPdfListCounters: [UUID: Int] = [:]
    private var lastSpaceListCounters: [UUID: Int] = [:]
    private var lastSpaceTransformCounters: [SpaceTransformSequenceKey: Int] = [:]
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
        lastPhotoListCounters[playerId] = nil
        lastPdfListCounters[playerId] = nil
        lastSpaceListCounters[playerId] = nil
        lastSpaceTransformCounters = lastSpaceTransformCounters.filter { $0.key.playerId != playerId }
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

    func canApplyPhotoList(from playerId: UUID, counter: Int) -> Bool {
        guard counter >= 0 else { return false }
        guard counter > 0 else { return true }
        return counter > (lastPhotoListCounters[playerId] ?? 0)
    }

    func recordPhotoList(counter: Int, from playerId: UUID) {
        guard counter > 0 else { return }
        lastPhotoListCounters[playerId] = counter
    }

    func resetPhotoListSequence() {
        lastPhotoListCounters.removeAll()
    }

    func canApplyPdfList(from playerId: UUID, counter: Int) -> Bool {
        guard counter >= 0 else { return false }
        guard counter > 0 else { return true }
        return counter > (lastPdfListCounters[playerId] ?? 0)
    }

    func recordPdfList(counter: Int, from playerId: UUID) {
        guard counter > 0 else { return }
        lastPdfListCounters[playerId] = counter
    }

    func resetPdfListSequence() {
        lastPdfListCounters.removeAll()
    }

    func canApplySpaceList(from playerId: UUID, counter: Int) -> Bool {
        guard counter >= 0 else { return false }
        guard counter > 0 else { return true }
        return counter > (lastSpaceListCounters[playerId] ?? 0)
    }

    func recordSpaceList(counter: Int, from playerId: UUID) {
        guard counter > 0 else { return }
        lastSpaceListCounters[playerId] = counter
    }

    func resetSpaceListSequence() {
        lastSpaceListCounters.removeAll()
    }

    func canApplySpaceTransform(from playerId: UUID, itemId: UUID, version: Int, counter: Int) -> Bool {
        guard counter >= 0 else { return false }
        guard counter > 0 else { return true }
        let key = SpaceTransformSequenceKey(playerId: playerId, itemId: itemId, version: version)
        return counter > (lastSpaceTransformCounters[key] ?? 0)
    }

    func recordSpaceTransform(from playerId: UUID, itemId: UUID, version: Int, counter: Int) {
        guard counter > 0 else { return }
        let key = SpaceTransformSequenceKey(playerId: playerId, itemId: itemId, version: version)
        lastSpaceTransformCounters[key] = counter
    }

    func resetSpaceTransformSequence() {
        lastSpaceTransformCounters.removeAll()
    }
}

final class MasterController: Sendable {
    private struct MapRecoveryBundle: Sendable {
        let full: NetworkCodableDataType
        let content: NetworkCodableDataType
        let state: NetworkCodableDataType
    }

    private enum MapRecoveryError: Error {
        case generationChanged
    }

    private static let maximumMapRecoveryCaptureAttempts = 3

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
        gameModel.resetPhotoListSequence()
        gameModel.resetPdfListSequence()
        gameModel.resetSpaceListSequence()
        gameModel.resetSpaceTransformSequence()
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
        await root.photoRoot.gameControllable.gameModel.setCurrent(players: players)
        await root.pdfRoot.gameControllable.gameModel.setCurrent(players: players)
        await root.spaceRoot.gameControllable.gameModel.setCurrent(players: players)
        await root.tableRoot.gameControllable.gameModel.setCurrent(players: players)
        await root.weatherRoot.gameControllable.gameModel.setCurrent(players: players)

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
        // Values are exchanged only as the joining player's Character. There
        // is no general Character/Value presentation protocol during a game.
        guard idType.type != .value else { return }

        // Map call sites from older modules/tests still construct the legacy
        // scale-only reference. Resolve the current background/content
        // fingerprints here so the Journal cache never falls back to that
        // mutable version.
        let resolvedIdType: NetworkCodableDataType
        if idType.type == .map, idType.assetVersion == nil {
            resolvedIdType = await root.mapRoot.mapGameControllable.shareMap(id: idType.id)
        } else if idType.type == .weather {
            // Weather's package identity comes from its linked Photo. Resolve it
            // here even for legacy/version-zero callers so the first-full cache
            // and Journal attachment use the canonical package version.
            resolvedIdType = await root.weatherRoot.weatherGameControllable.shareWeather(id: idType.id)
        } else {
            resolvedIdType = idType
        }
        if resolvedIdType.type == .space {
            let masterId = await root.gameModel.gameConfig.id
            await root.spaceRoot.spaceGameControllable.setMasterVersion(
                itemId: resolvedIdType.id,
                version: resolvedIdType.effectiveAssetVersion,
                masterId: masterId
            )
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
        case .map, .photo, .pdf, .space, .weather:
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
        case .weather:
            try await root.weatherRoot.weatherGameControllable.createWeatherGameData(for: idType.id)
        default:
            nil
        }
    }
    
    func game(message: NetworkCodableDataType, actionType: RPGMessageActionType, playerId: UUID? = nil) async {
        // Weather is immutable during a game. It is presented and repaired via
        // reveal messages only; live update messages are not supported yet.
        // Character/Value updates likewise have no in-game protocol; the only
        // supported Value exchange is the player join handshake below.
        guard message.type != .table, message.type != .value, message.type != .weather else { return }
        if message.type == .audio, actionType == .playAudio {
            await requestAudioPlay(message)
            return
        }
        if message.type == .space, actionType == .spaceTransform {
            guard await root.spaceRoot.spaceGameControllable.isValidSpaceTransform(message),
                  await root.spaceRoot.gameControllable.gameModel.currentItemId == message.id
            else { return }
            let version = await root.spaceRoot.gameControllable.networkVersion(for: message.id)
            let canonical = NetworkCodableDataType(
                id: message.id,
                type: .space,
                version: version,
                data: message.data
            )
            await send(type: .update, subtype: .spaceTransform, updated: canonical, playerId: playerId)
            return
        }
        await send(type: .update, subtype: actionType, updated: message, playerId: playerId)
    }
    
    func send(updated: NetworkCodableDataType) async {
        guard updated.type != .value else { return }
        await send(type: .store, subtype: .store, updated: updated)
    }
    
    func send(type: RPGMessageType, subtype: RPGMessageActionType, updated: NetworkCodableDataType, connectionId: ConnectionController.ID? = nil, playerId: UUID? = nil, authoritativeMaster: Bool? = nil) async {
        // Tables are immutable during a game. Their complete state is exchanged
        // only through reveal/store requests; accepting an update would bypass
        // the versioned canonical-package handshake.
        guard type != .update || updated.type != .table else { return }

        let counter = await gameModel.nextMessageCounter()
        Logger.networking.debug("MasterController: Send \(counter, privacy: .public): \(type.debugDescription, privacy: .public) - \(subtype.debugDescription, privacy: .public) for \(updated.type.token, privacy: .public) -> \(updated.id, privacy: .public)")

        // Built from local state in one MainActor hop; a playerId becomes the
        // message target so only the addressee processes it.
        let networtData = await MainActor.run {
            root.gameModel.outgoingMessage(counter: counter, type: type, subType: subtype, asMaster: authoritativeMaster ?? !asProxy, targetId: playerId, data: updated)
        }

        if !asProxy,
           networtData.sender.isMaster,
           type == .update,
           subtype == .spaceTransform {
            guard await root.spaceRoot.spaceGameControllable.applySpaceTransform(
                data: networtData.data,
                counter: networtData.counter
            ) else { return }
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
        await root.photoRoot.photoGameControllable.removePhotoReports(for: playerId)
        await root.pdfRoot.pdfGameControllable.removePdfReports(for: playerId)
        await root.spaceRoot.spaceGameControllable.removeSpaceReports(for: playerId)
        await root.tableRoot.gameControllable.gameModel.removePlayerReport(for: playerId)
        await root.weatherRoot.gameControllable.gameModel.removePlayerReport(for: playerId)
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
            if let requestedData = try await handle(model, connectionId: event.connectionId) {
                try Task.checkCancellation()
                if requestedData.data != nil, requestedData.type != .map {
                    // The full payload went out — a later reshow can rely on
                    // the reference no matter which path delivered first.
                    // Map is deliberately excluded: all Map request responses
                    // are requester-only repairs (including photo-free generic
                    // updates). Only show(for:) publishes the full Map package
                    // to the group and may establish the shared sent baseline.
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
    func handle(
        _ model: GameNetworkModel,
        connectionId: ConnectionController.ID? = nil
    ) async throws -> NetworkCodableDataType? {
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
            return try await handleMap(model, connectionId: connectionId)
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
    
    func handleMap(
        _ model: GameNetworkModel,
        connectionId: ConnectionController.ID? = nil
    ) async throws -> NetworkCodableDataType? {
        if model.subType == .ok {
            // Maps are session-memory presentations, not player-owned assets.
            // Acknowledgements therefore carry no availability meaning and
            // must not populate the generic player-report store.
            return nil
        }
        guard model.subType != .failed else { return nil }
        
        switch model.type {
        case .reveal:
            let recovery = try await stableMapRecoveryBundle(for: model.data.id)
            guard mapGeneration(of: recovery.full, matches: model.data) else {
                // The requested generation disappeared while the player was
                // asking for it. A proxy must defer to the real master; the
                // real master explicitly publishes its new generation so the
                // requester supersedes the now-impossible pending repair.
                guard !asProxy else { throw MapRecoveryError.generationChanged }
                await sendFreshMapRecovery(recovery, connectionId: connectionId)
                return nil
            }
            if model.subType == .mapState {
                // Targeted at the recovering player: everyone else already has
                // the map, and over SharePlay an untargeted full payload would
                // be skipped as identical to the published journal attachment.
                await send(
                    type: .reveal,
                    subtype: .store,
                    updated: recovery.full,
                    connectionId: connectionId,
                    playerId: model.sender.id,
                    authoritativeMaster: true
                )
                // Send the live map state (not the request echo, whose data is
                // nil) so the recovering player syncs room visibility and pins.
                // Targeted: the other players are already up to date.
                await send(
                    type: .update,
                    subtype: .generic,
                    updated: recovery.content,
                    connectionId: connectionId,
                    playerId: model.sender.id,
                    authoritativeMaster: true
                )
                await send(
                    type: .update,
                    subtype: .mapState,
                    updated: recovery.state,
                    connectionId: connectionId,
                    playerId: model.sender.id,
                    authoritativeMaster: true
                )
            } else {
                return recovery.full
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
                let update = await root.mapRoot.mapGameControllable.networkMapContentUpdate(
                    for: model.data.id
                )
                guard mapGeneration(of: update, matches: model.data) else {
                    guard !asProxy else { throw MapRecoveryError.generationChanged }
                    await sendFreshMapRecovery(
                        try await stableMapRecoveryBundle(for: model.data.id),
                        connectionId: connectionId
                    )
                    return nil
                }
                return update
            case .mapState:
                // never get from players mapState updates, only as resend from SharePlay?
                break
            case .mapPin:
                if await root.mapRoot.mapGameControllable.updatePinIfCurrentGeneration(
                    itemId: model.data.id,
                    data: model.data,
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

    /// Captures the full package, structural snapshot, and live state from one
    /// Map generation. Each component suspends independently, so compare their
    /// fingerprints and retry instead of sending a torn recovery sequence.
    private func stableMapRecoveryBundle(for itemId: UUID) async throws -> MapRecoveryBundle {
        for _ in 0..<Self.maximumMapRecoveryCaptureAttempts {
            try Task.checkCancellation()
            let full: NetworkCodableDataType
            do {
                full = try await root.mapRoot.mapGameControllable.createMapGameData(for: itemId)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Map package export has its own bounded stability check. If
                // an edit crosses that capture window, retry the whole bundle
                // so the player's coalesced repair is not silently dropped.
                continue
            }
            let content = await root.mapRoot.mapGameControllable.networkMapContentUpdate(
                for: itemId
            )
            let state = await root.mapRoot.mapGameControllable.networkMapUpdate(for: itemId)
            guard full.id == itemId,
                  content.id == itemId,
                  state.id == itemId,
                  full.assetVersion == content.assetVersion,
                  full.assetVersion == state.assetVersion,
                  full.contentVersion == content.contentVersion,
                  full.contentVersion == state.contentVersion
            else { continue }

            return MapRecoveryBundle(full: full, content: content, state: state)
        }
        throw MapRecoveryError.generationChanged
    }

    /// Nil fingerprints are legacy requests and remain compatible. Current
    /// peers provide both values, which must match the captured response.
    private func mapGeneration(
        of response: NetworkCodableDataType,
        matches request: NetworkCodableDataType
    ) -> Bool {
        if let requestedAssetVersion = request.assetVersion,
           response.assetVersion != requestedAssetVersion {
            return false
        }
        if let requestedContentVersion = request.contentVersion,
           response.contentVersion != requestedContentVersion {
            return false
        }
        return true
    }

    /// The requested generation no longer exists. On a direct master, publish
    /// the newly captured generation as a fresh intent. A direct LAN connection
    /// keeps this physical transfer requester-only; SharePlay broadcasts the
    /// rare supersession so every participant advances consistently.
    private func sendFreshMapRecovery(
        _ recovery: MapRecoveryBundle,
        connectionId: ConnectionController.ID?
    ) async {
        await send(
            type: .reveal,
            subtype: .show,
            updated: recovery.full,
            connectionId: connectionId,
            authoritativeMaster: true
        )
        await send(
            type: .update,
            subtype: .generic,
            updated: recovery.content,
            connectionId: connectionId,
            authoritativeMaster: true
        )
        await send(
            type: .update,
            subtype: .mapState,
            updated: recovery.state,
            connectionId: connectionId,
            authoritativeMaster: true
        )
    }

    func handlePdf(_ model: GameNetworkModel) async throws -> NetworkCodableDataType? {
        if model.subType == .ok {
            let masterId = await root.gameModel.gameConfig.id
            let baseline = await root.pdfRoot.gameControllable.networkVersion(for: model.data.id)
            await root.pdfRoot.pdfGameControllable.setMasterVersion(
                itemId: model.data.id,
                version: baseline,
                masterId: masterId
            )
            await root.pdfRoot.pdfGameControllable.markPdfAvailable(
                itemId: model.data.id,
                version: model.data.effectiveAssetVersion,
                for: [model.sender.id],
                masterId: masterId
            )
            return nil
        }
        guard model.subType != .failed else { return nil }

        let masterId = await root.gameModel.gameConfig.id
        switch model.type {
        case .reveal:
            let reference = await root.pdfRoot.gameControllable.share(id: model.data.id)
            await root.pdfRoot.pdfGameControllable.setMasterVersion(
                itemId: reference.id,
                version: reference.effectiveAssetVersion,
                masterId: masterId
            )
            let senderIsAvailable = await root.pdfRoot.pdfGameControllable.isPdfAvailable(
                itemId: model.data.id,
                for: model.sender.id,
                masterId: masterId
            )
            let matchesBaseline = model.data.effectiveAssetVersion == reference.effectiveAssetVersion

            if senderIsAvailable, matchesBaseline {
                if model.data.data != nil {
                    await gameModel.markSentGameItem(
                        type: .pdf,
                        id: model.data.id,
                        version: reference.effectiveAssetVersion
                    )
                }
                // Remote transports already delivered the peer reveal. Only
                // the co-located player controller needs the relay.
                await root.networkStore.sendLocalPlayer(model)
                return nil
            }

            // Peer bytes never establish or replace the game master's PDF.
            guard await root.pdfRoot.gameControllable.hasLocalFileData(for: model.data.id) else { return nil }
            if let canonical = try? await root.pdfRoot.gameControllable.createGameData(for: model.data.id) {
                await gameModel.markSentGameItem(
                    type: .pdf,
                    id: canonical.id,
                    version: canonical.effectiveAssetVersion
                )
                await send(type: .reveal, subtype: .show, updated: canonical)
            }
            return nil
        case .store:
            guard await root.pdfRoot.gameControllable.hasLocalFileData(for: model.data.id) else { return nil }
            return try await root.pdfRoot.gameControllable.createGameData(for: model.data.id)
        case .update:
            switch model.subType {
            case .pdfList:
                guard await applyPdfList(model) else { return nil }
                let pdfList = await root.pdfRoot.pdfGameControllable.pdfList(
                    allPlayers: true,
                    with: masterId
                )
                await send(type: .update, subtype: .pdfList, updated: pdfList)
            case .generic:
                // Compatibility with older players: answer with the canonical
                // master asset, but never import the peer's bytes.
                guard await root.pdfRoot.gameControllable.hasLocalFileData(for: model.data.id) else { return nil }
                if let canonical = try? await root.pdfRoot.gameControllable.createGameData(for: model.data.id) {
                    await gameModel.markSentGameItem(
                        type: .pdf,
                        id: canonical.id,
                        version: canonical.effectiveAssetVersion
                    )
                    await send(type: .reveal, subtype: .show, updated: canonical)
                }
            default:
                break
            }
            return nil
        }
    }

    @MainActor
    private func applyPdfList(_ model: GameNetworkModel) async -> Bool {
        guard !model.sender.isMaster,
              gameModel.canApplyPdfList(from: model.sender.id, counter: model.counter),
              await root.pdfRoot.pdfGameControllable.applyPdfList(
                  data: model.data,
                  for: model.sender.id,
                  with: root.gameModel.gameConfig.id,
                  authoritative: false
              )
        else { return false }

        gameModel.recordPdfList(counter: model.counter, from: model.sender.id)
        return true
    }

    func handlePhoto(_ model: GameNetworkModel) async throws -> NetworkCodableDataType? {
        if model.subType == .ok {
            let masterId = await root.gameModel.gameConfig.id
            let baseline = await root.photoRoot.gameControllable.networkVersion(for: model.data.id)
            await root.photoRoot.photoGameControllable.setMasterVersion(
                itemId: model.data.id,
                version: baseline,
                masterId: masterId
            )
            await root.photoRoot.photoGameControllable.markPhotoAvailable(
                itemId: model.data.id,
                version: model.data.effectiveAssetVersion,
                for: [model.sender.id],
                masterId: masterId
            )
            return nil
        }
        guard model.subType != .failed else { return nil }

        let masterId = await root.gameModel.gameConfig.id
        switch model.type {
        case .reveal:
            let reference = await root.photoRoot.gameControllable.share(id: model.data.id)
            await root.photoRoot.photoGameControllable.setMasterVersion(
                itemId: reference.id,
                version: reference.effectiveAssetVersion,
                masterId: masterId
            )
            let senderIsAvailable = await root.photoRoot.photoGameControllable.isPhotoAvailable(
                itemId: model.data.id,
                for: model.sender.id,
                masterId: masterId
            )
            let matchesBaseline = model.data.effectiveAssetVersion == reference.effectiveAssetVersion

            if senderIsAvailable, matchesBaseline {
                // LAN and SharePlay forwarding already distributed the player's
                // reveal (and its Journal attachment). Only the game master's
                // co-located player controller did not receive that fan-out.
                if model.data.data != nil {
                    await gameModel.markSentGameItem(
                        type: .photo,
                        id: model.data.id,
                        version: reference.effectiveAssetVersion
                    )
                }
                await root.networkStore.sendLocalPlayer(model)
                return nil
            }

            // Never import a player's competing version into the master. An
            // absent/mismatched sender is a request for the master's baseline,
            // which is published as the authoritative group reveal.
            if let canonical = try? await root.photoRoot.gameControllable.createGameData(for: model.data.id) {
                await gameModel.markSentGameItem(
                    type: .photo,
                    id: canonical.id,
                    version: canonical.effectiveAssetVersion
                )
                await send(type: .reveal, subtype: .show, updated: canonical)
            }
            return nil
        case .store:
            return try await root.photoRoot.gameControllable.createGameData(for: model.data.id)
        case .update:
            switch model.subType {
            case .photoList:
                guard await applyPhotoList(model) else { return nil }
                let photoList = await root.photoRoot.photoGameControllable.photoList(
                    allPlayers: true,
                    with: masterId
                )
                await send(type: .update, subtype: .photoList, updated: photoList)
            case .generic:
                // Compatibility with older players that uploaded a generic
                // photo update. Their bytes are never authoritative.
                if let canonical = try? await root.photoRoot.gameControllable.createGameData(for: model.data.id) {
                    await gameModel.markSentGameItem(
                        type: .photo,
                        id: canonical.id,
                        version: canonical.effectiveAssetVersion
                    )
                    await send(type: .reveal, subtype: .show, updated: canonical)
                }
            default:
                break
            }
            return nil
        }
    }

    @MainActor
    private func applyPhotoList(_ model: GameNetworkModel) async -> Bool {
        guard !model.sender.isMaster,
              gameModel.canApplyPhotoList(from: model.sender.id, counter: model.counter),
              await root.photoRoot.photoGameControllable.applyPhotoList(
                  data: model.data,
                  for: model.sender.id,
                  with: root.gameModel.gameConfig.id,
                  authoritative: false
              )
        else { return false }

        gameModel.recordPhotoList(counter: model.counter, from: model.sender.id)
        return true
    }
    
    func handleTable(_ model: GameNetworkModel) async throws -> NetworkCodableDataType? {
        guard model.type != .update else { return nil }

        if model.subType == .ok {
            let currentVersion = await root.tableRoot.gameControllable.networkVersion(for: model.data.id)
            guard model.data.version != 0, model.data.version == currentVersion else { return nil }
            await root.tableRoot.gameControllable.report(itemId: model.data.id, for: model.sender.id)
            return nil
        }
        guard model.subType != .failed else { return nil }
        
        switch model.type {
        case .reveal, .store:
            return try await root.tableRoot.gameControllable.createGameData(for: model.data.id)
        case .update:
            return nil
        }
    }

    func handleValue(_ model: GameNetworkModel) async throws -> NetworkCodableDataType? {
        // Character/Value messages have one normal-game purpose: synchronize
        // the selected Character when a player joins. Presentation, loot,
        // result, acknowledgement, and live-update variants are intentionally
        // unsupported until they get their own protocols.
        guard model.type == .update,
              model.subType == .store,
              model.senderType == .player,
              let characterId = model.sender.characterId,
              characterId == model.data.id
        else { return nil }

        if model.data.data == nil {
            let localVersion = await root.characterRoot.gameControllable.networkVersion(for: characterId)
            // Exact versions mean the master already owns this Character
            // package. Silence is the successful response; only a mismatch
            // asks the originating player for its potentially large package.
            guard localVersion != model.data.version else {
                await root.mapRoot.mapGameControllable.setPlayerPin(
                    for: model.sender.id,
                    name: model.senderName,
                    characterId: characterId
                )
                await publishCurrentMapAfterPlayerPinChange()
                return nil
            }
            return model.data
        }

        try await root.characterRoot.valueGameControllable.updatePlayer(data: model.data)
        await root.mapRoot.mapGameControllable.setPlayerPin(
            for: model.sender.id,
            name: model.senderName,
            characterId: characterId
        )
        await publishCurrentMapAfterPlayerPinChange()
        return nil
    }

    /// Character synchronization can finish after resetPlayers() created and
    /// broadcast a pin without its Character photo. Re-publish both the
    /// structural pin metadata and authoritative live state once the Character
    /// is known so every peer replaces that bootstrap copy immediately.
    private func publishCurrentMapAfterPlayerPinChange() async {
        guard let mapId = await root.mapRoot.mapGameControllable.gameModel.currentItemId else {
            return
        }
        await send(
            type: .update,
            subtype: .generic,
            updated: await root.mapRoot.mapGameControllable.networkMapContentUpdate(for: mapId)
        )
        await send(
            type: .update,
            subtype: .mapState,
            updated: root.mapRoot.mapGameControllable.networkMapUpdate(for: mapId)
        )
    }
    
    func handleWeather(_ model: GameNetworkModel) async throws -> NetworkCodableDataType? {
        if model.subType == .ok {
            let baseline = await root.weatherRoot.weatherGameControllable.weatherVersion(for: model.data.id)
            guard model.data.version == baseline else { return nil }
            await root.weatherRoot.gameControllable.report(itemId: model.data.id, for: model.sender.id)
            return nil
        }
        guard model.subType != .failed else { return nil }

        switch model.type {
        case .reveal, .store:
            // A player request names only the Weather. Always rebuild the full
            // canonical package from the master; inbound peer bytes are ignored.
            return try await root.weatherRoot.weatherGameControllable.createWeatherGameData(for: model.data.id)
        case .update:
            // Weather is immutable for the lifetime of a game. Live update
            // messages are intentionally unsupported for now.
            return nil
        }
    }
    
    func handleSpace(_ model: GameNetworkModel) async throws -> NetworkCodableDataType? {
        if model.subType == .ok {
            let masterId = await root.gameModel.gameConfig.id
            let baseline = await root.spaceRoot.gameControllable.networkVersion(for: model.data.id)
            await root.spaceRoot.spaceGameControllable.setMasterVersion(
                itemId: model.data.id,
                version: baseline,
                masterId: masterId
            )
            await root.spaceRoot.spaceGameControllable.markSpaceAvailable(
                itemId: model.data.id,
                version: model.data.effectiveAssetVersion,
                for: [model.sender.id],
                masterId: masterId
            )
            return nil
        }
        guard model.subType != .failed else { return nil }

        let masterId = await root.gameModel.gameConfig.id
        switch model.type {
        case .reveal:
            let playerSharingEnabled = await root.gameModel.gameControl.features.spaceSharing
            let reference = await root.spaceRoot.gameControllable.share(id: model.data.id)
            await root.spaceRoot.spaceGameControllable.setMasterVersion(
                itemId: reference.id,
                version: reference.effectiveAssetVersion,
                masterId: masterId
            )
            let senderIsAvailable = await root.spaceRoot.spaceGameControllable.isSpaceAvailable(
                itemId: model.data.id,
                for: model.sender.id,
                masterId: masterId
            )
            let matchesBaseline = model.data.effectiveAssetVersion == reference.effectiveAssetVersion

            if playerSharingEnabled, senderIsAvailable, matchesBaseline {
                if model.data.data != nil {
                    await gameModel.markSentGameItem(
                        type: .space,
                        id: model.data.id,
                        version: reference.effectiveAssetVersion
                    )
                }
                // The transport already delivered the peer reveal to remote
                // participants. Only the co-located player missed that fan-out.
                await root.networkStore.sendLocalPlayer(model)
                return nil
            }

            if !playerSharingEnabled {
                // `spaceSharing` controls player-initiated presentations, not
                // delivery of a Space the master already presented. A player
                // missing the Journal attachment answers the master's reveal
                // with this data-less request. Return the canonical package so
                // the common request path targets it only at that player.
                guard model.data.data == nil, matchesBaseline else { return nil }
                return try? await root.spaceRoot.gameControllable.createGameData(for: model.data.id)
            }

            // The game master's file/version is always canonical. A peer with no
            // matching availability report is asking the master to publish it.
            if let canonical = try? await root.spaceRoot.gameControllable.createGameData(for: model.data.id) {
                await gameModel.markSentGameItem(
                    type: .space,
                    id: canonical.id,
                    version: canonical.effectiveAssetVersion
                )
                await send(type: .reveal, subtype: .show, updated: canonical)
            }
            return nil
        case .store:
            return try await root.spaceRoot.gameControllable.createGameData(for: model.data.id)
        case .update:
            switch model.subType {
            case .spaceList:
                guard await applySpaceList(model) else { return nil }
                let spaceList = await root.spaceRoot.spaceGameControllable.spaceList(
                    allPlayers: true,
                    with: masterId
                )
                await send(type: .update, subtype: .spaceList, updated: spaceList)
            case .spaceTransform:
                guard model.sender.role == .player,
                      await root.gameModel.gameControl.features.spaceSharing,
                      await root.spaceRoot.spaceGameControllable.isValidSpaceTransform(model.data)
                else { return nil }

                let baseline = await root.spaceRoot.gameControllable.networkVersion(for: model.data.id)
                await root.spaceRoot.spaceGameControllable.setMasterVersion(
                    itemId: model.data.id,
                    version: baseline,
                    masterId: masterId
                )
                guard model.data.effectiveAssetVersion == baseline,
                      await root.spaceRoot.spaceGameControllable.isSpaceAvailable(
                          itemId: model.data.id,
                          for: model.sender.id,
                          masterId: masterId
                      ),
                      await gameModel.canApplySpaceTransform(
                          from: model.sender.id,
                          itemId: model.data.id,
                          version: baseline,
                          counter: model.counter
                      )
                else { return nil }

                await gameModel.recordSpaceTransform(
                    from: model.sender.id,
                    itemId: model.data.id,
                    version: baseline,
                    counter: model.counter
                )
                let canonical = NetworkCodableDataType(
                    id: model.data.id,
                    type: .space,
                    version: baseline,
                    data: model.data.data
                )
                await send(type: .update, subtype: .spaceTransform, updated: canonical)
            case .generic:
                // Compatibility with older players. Peer bytes never replace the
                // game master's canonical Space asset.
                guard await root.gameModel.gameControl.features.spaceSharing else { return nil }
                if let canonical = try? await root.spaceRoot.gameControllable.createGameData(for: model.data.id) {
                    await gameModel.markSentGameItem(
                        type: .space,
                        id: canonical.id,
                        version: canonical.effectiveAssetVersion
                    )
                    await send(type: .reveal, subtype: .show, updated: canonical)
                }
            default:
                break
            }
            return nil
        }
    }

    @MainActor
    private func applySpaceList(_ model: GameNetworkModel) async -> Bool {
        guard !model.sender.isMaster,
              gameModel.canApplySpaceList(from: model.sender.id, counter: model.counter),
              await root.spaceRoot.spaceGameControllable.applySpaceList(
                  data: model.data,
                  for: model.sender.id,
                  with: root.gameModel.gameConfig.id,
                  authoritative: false
              )
        else { return false }

        gameModel.recordSpaceList(counter: model.counter, from: model.sender.id)
        return true
    }
}

// MARK: - MasterNetworkProxyStoreDelegate

extension MasterController: MasterNetworkProxyControllerDelegate {
    func readyProxy(for connectionId: ConnectionController.ID) async {
        Logger.networking.debug("MasterController: Proxy Ready for \(connectionId, privacy: .public)")
        await replayCurrentPresentation(to: connectionId)
        guard let characterId = await root.gameModel.gamePlayer.characterId else { return }
        if let data = try? await root.characterRoot.gameControllable.createGameData(for: characterId) {
            await send(
                type: .update,
                subtype: .store,
                updated: data,
                connectionId: connectionId,
                authoritativeMaster: true
            )
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
        if model.isAcknowledgement || model.subType == .screen || model.subType == .audioList || model.subType == .photoList || model.subType == .pdfList || model.subType == .spaceList {
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
            guard await root.mapRoot.mapGameControllable.updatePinIfCurrentGeneration(
                itemId: model.data.id,
                data: model.data,
                playerId: hostId
            ) else {
                return true
            }
            await remapUpstream(model)
            return true
        }

        if model.data.type == .space, model.type == .update, model.subType == .spaceTransform {
            // Remap upstream without applying the peer counter locally. The real
            // master sends the canonical, globally ordered pose back to the host
            // and every proxy client.
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
        // This message came from a proxy client. Sending it upstream must not
        // broadcast the request back to that same proxy (or its siblings),
        // otherwise every mirror can request the same missing payload again.
        await playerController.send(
            type: model.type,
            subType: model.subType,
            updated: model.data,
            relayToProxyClients: false
        )
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
            guard await root.mapRoot.mapGameControllable.missingMapImages(itemId: data.id).isEmpty else {
                return false
            }
            let localReference = await root.mapRoot.mapGameControllable.shareMap(id: data.id)
            if let requestedAssetVersion = data.assetVersion,
               requestedAssetVersion != localReference.assetVersion {
                return false
            }
            if let requestedContentVersion = data.contentVersion,
               requestedContentVersion != localReference.contentVersion {
                return false
            }
            return true
        case .weather:
            return await root.weatherRoot.weatherGameControllable.isWeatherAvailable(
                itemId: data.id,
                version: data.version
            )
        case .table:
            // A player's current-session Table is a CRDT merge with its local
            // copy and may no longer equal the game master's canonical package.
            // Always forward proxy repairs to the real master.
            return false
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
            // Tables are rare and noncritical, so a reconnect can wait for the
            // game master to show the Table again. More importantly, a proxy
            // host keeps the player's CRDT-merged copy here; deriving a replay
            // version from that copy would advertise a baseline the real game
            // master never sent.
            reference = nil
        case .value:
            // Values are not presentations. A proxy receives the host's full
            // Character through readyProxy(for:) immediately below instead.
            reference = nil
        case .weather:
            reference = if let id = await root.weatherRoot.gameControllable.gameModel.currentItemId {
                await root.weatherRoot.weatherGameControllable.shareWeather(id: id)
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
        } else if presentation == .space,
                  let transform = await root.spaceRoot.spaceGameControllable.latestSpaceTransform(
                      for: reference.id,
                      version: reference.effectiveAssetVersion
                  ) {
            // Messenger transforms have no history. Replay the retained pose
            // after the asset reference; the Space viewer also retains it while
            // the file-backed entity is still loading.
            await send(
                type: .update,
                subtype: .spaceTransform,
                updated: transform,
                connectionId: connectionId,
                authoritativeMaster: true
            )
        }
    }
}
