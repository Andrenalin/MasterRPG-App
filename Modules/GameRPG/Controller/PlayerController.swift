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
    private struct PresentationIntent {
        let module: NetworkModules
        let counter: Int
        let itemId: UUID
        let version: Int
    }

    private struct PendingMapContentUpdate: Sendable {
        let data: NetworkCodableDataType
        let counter: Int
    }

    var gameUpdateType: NetworkModules = .none
    var messageCounter: Int = 0
    private var outgoingMessageCounter: Int = 1
    private var lastMasterStateCounters: [UUID: Int] = [:]
    private var presentationIntents: [UUID: PresentationIntent] = [:]
    var lostMaster: Bool = true
    var hasSendPlayer = false
    var asGameMaster = false
    var sendCharacterTask: Task<Void, Never>?
    var sendCharacterTaskId: UUID?
    var proxyFocusTask: Task<Void, Never>?
    var proxyFocusTaskId: UUID?
    // Map ids with an in-flight full-map re-request, so a burst of mapState
    // messages cannot trigger a request storm. Cleared when map data arrives.
    var pendingMapRequests: Set<UUID> = []
    // Audio reveals waiting for a full payload. SharePlay journals deliver the
    // bytes as a non-presenting store so every participant and proxy can save it.
    var pendingAudioRequests: Set<UUID> = []
    // Photo ids already requested for repair. An id is only released when the
    // repair actually produced a local file — a permanently failing photo is
    // requested once instead of looping master responses forever.
    var requestedRepairIds: Set<UUID> = []
    // Maps whose background photo was missing after a delivery and triggered one
    // full-map re-request. The background belongs exclusively to the full map
    // package, so the single retry prevents a full-payload request loop.
    var requestedFullMapIds: Set<UUID> = []
    /// Latest structural update received before its Journal-backed base map.
    /// Only one value per map is retained, so interleaved chunk streams cannot
    /// roll a newer editor refresh back.
    private var pendingMapContentUpdates: [UUID: PendingMapContentUpdate] = [:]
    private var lastMapContentUpdateCounters: [UUID: Int] = [:]
    private var lastFullMapContentCounters: [UUID: Int] = [:]
    private var mapContentVersions: [UUID: Int] = [:]

    func increaseMessageCounter() {
        messageCounter += 1
    }

    func nextOutgoingMessageCounter() -> Int {
        defer { outgoingMessageCounter += 1 }
        return outgoingMessageCounter
    }

    func shouldApplyMasterState(from masterId: UUID, counter: Int) -> Bool {
        guard counter > 0 else { return true }
        guard counter > (lastMasterStateCounters[masterId] ?? 0) else { return false }
        lastMasterStateCounters[masterId] = counter
        return true
    }

    func resetMasterStateSequence() {
        lastMasterStateCounters.removeAll()
    }

    /// Accepts presentation content according to the latest master intent, not
    /// according to which transport happened to finish first.
    ///
    /// A repair reveal's freshly minted counter must
    /// not make an older item current again, so it is accepted only when it
    /// matches the desired item. Older untargeted content for that same desired
    /// item remains useful as a delayed full-payload delivery.
    func shouldProcessPresentation(
        from masterId: UUID,
        module: NetworkModules,
        itemId: UUID,
        version: Int,
        counter: Int,
        isRepair: Bool,
        allowsUnversionedStateRepair: Bool = false
    ) -> Bool {
        guard let current = presentationIntents[masterId] else {
            presentationIntents[masterId] = PresentationIntent(
                module: module,
                counter: counter,
                itemId: itemId,
                version: version
            )
            return true
        }

        if isRepair {
            return acceptsCurrentPresentation(
                current,
                from: masterId,
                module: module,
                itemId: itemId,
                version: version,
                allowsUnversionedStateRepair: allowsUnversionedStateRepair
            )
        }

        // Counter zero is the unsequenced legacy format. Preserve compatibility
        // by treating its latest arrival as the current intent.
        guard counter > 0 else {
            presentationIntents[masterId] = PresentationIntent(
                module: module,
                counter: counter,
                itemId: itemId,
                version: version
            )
            return true
        }

        if counter < current.counter {
            return acceptsCurrentPresentation(
                current,
                from: masterId,
                module: module,
                itemId: itemId,
                version: version
            )
        }
        if counter == current.counter {
            return acceptsCurrentPresentation(
                current,
                from: masterId,
                module: module,
                itemId: itemId,
                version: version
            )
        }

        presentationIntents[masterId] = PresentationIntent(
            module: module,
            counter: counter,
            itemId: itemId,
            version: version
        )
        return true
    }

    private func acceptsCurrentPresentation(
        _ current: PresentationIntent,
        from masterId: UUID,
        module: NetworkModules,
        itemId: UUID,
        version: Int,
        allowsUnversionedStateRepair: Bool = false
    ) -> Bool {
        guard current.module == module, current.itemId == itemId else { return false }
        guard current.version == 0 ||
                version == current.version ||
                (allowsUnversionedStateRepair && version == 0)
        else { return false }

        // Version zero means the legacy intent did not provide a fingerprint.
        // Once matching bytes arrive, retain their exact version so a later
        // same-item payload cannot replace them arbitrarily.
        if current.version == 0, version != 0 {
            presentationIntents[masterId] = PresentationIntent(
                module: current.module,
                counter: current.counter,
                itemId: current.itemId,
                version: version
            )
        }
        return true
    }

    func resetPresentationSequence() {
        presentationIntents.removeAll()
    }

    func queueMapContentUpdate(_ data: NetworkCodableDataType, counter: Int) {
        let appliedCounter = max(
            lastMapContentUpdateCounters[data.id] ?? 0,
            lastFullMapContentCounters[data.id] ?? 0
        )
        guard counter == 0 || counter > appliedCounter else { return }
        if let current = pendingMapContentUpdates[data.id], counter != 0, current.counter >= counter {
            return
        }
        pendingMapContentUpdates[data.id] = PendingMapContentUpdate(data: data, counter: counter)
    }

    func pendingMapContentUpdate(for itemId: UUID) -> (data: NetworkCodableDataType, counter: Int)? {
        guard let pending = pendingMapContentUpdates[itemId] else { return nil }
        return (pending.data, pending.counter)
    }

    func discardPendingMapContentUpdate(itemId: UUID) {
        pendingMapContentUpdates[itemId] = nil
    }

    func shouldApplyMapContentUpdate(itemId: UUID, counter: Int) -> Bool {
        counter == 0 || counter > max(
            lastMapContentUpdateCounters[itemId] ?? 0,
            lastFullMapContentCounters[itemId] ?? 0
        )
    }

    /// A Journal-backed full map may finish after a newer messenger mapUpdate.
    /// Importing that older snapshot would roll structural metadata back even
    /// though its background asset is still valid.
    func shouldImportFullMapContent(itemId: UUID, counter: Int) -> Bool {
        counter == 0 || counter > max(
            lastMapContentUpdateCounters[itemId] ?? 0,
            lastFullMapContentCounters[itemId] ?? 0
        )
    }

    func markMapContentUpdateApplied(itemId: UUID, counter: Int, contentVersion: Int?) {
        if counter > 0 {
            lastMapContentUpdateCounters[itemId] = counter
        }
        if let contentVersion {
            mapContentVersions[itemId] = contentVersion
        }
        pendingMapContentUpdates[itemId] = nil
    }

    func recordFullMapContentVersion(itemId: UUID, contentVersion: Int?, counter: Int) {
        guard shouldImportFullMapContent(itemId: itemId, counter: counter) else { return }
        if let contentVersion {
            mapContentVersions[itemId] = contentVersion
        }
        if counter > 0 {
            lastFullMapContentCounters[itemId] = max(lastFullMapContentCounters[itemId] ?? 0, counter)
        }
    }

    func hasMapContentVersion(itemId: UUID, contentVersion: Int?) -> Bool {
        guard let contentVersion else { return true }
        return mapContentVersions[itemId] == contentVersion
    }

    func resetMapContentSequence() {
        pendingMapContentUpdates.removeAll()
        lastMapContentUpdateCounters.removeAll()
        lastFullMapContentCounters.removeAll()
        mapContentVersions.removeAll()
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
    // `unowned` crashed here when in-flight controller tasks outlived
    // stopGame()/teardown. A strong reference keeps GameRoot alive until the
    // last task finishes.
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
        gameModel.sendCharacterTaskId = nil
        gameModel.proxyFocusTask?.cancel()
        gameModel.proxyFocusTask = nil
        gameModel.proxyFocusTaskId = nil
        await root.networkProxyStore.stopGame()
        await root.networkStore.stopGame()
        await root.adventureRoot.adventureGameControllable.resetGame()
        gameModel.hasSendPlayer = false
        gameModel.pendingMapRequests = []
        gameModel.pendingAudioRequests = []
        gameModel.requestedRepairIds = []
        gameModel.requestedFullMapIds = []
        gameModel.resetMasterStateSequence()
        gameModel.resetPresentationSequence()
        gameModel.resetMapContentSequence()
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
        await send(type: .store, subType: .store, updated: updated)
    }
    
    func game(message: NetworkCodableDataType, actionType: RPGMessageActionType) async {
        await send(type: .update, subType: actionType, updated: message)
    }
    
    func send(screen: AKImage, responseCounter: Int) async {
        let data = NetworkCodableDataType(id: UUID(), type: .game, version: 0, data: screen.jpegData(compressionQuality: 0.5))
        await send(counter: responseCounter, type: .store, subType: .screen, updated: data)
    }
    
    func send(counter: Int? = nil, type: RPGMessageType, subType: RPGMessageActionType = .show, updated: NetworkCodableDataType, useJournal: Bool = false) async {
        let outgoingCounter = await MainActor.run {
            counter ?? gameModel.nextOutgoingMessageCounter()
        }
        Logger.networking.debug("PlayerController: Send \(outgoingCounter, privacy: .public): \(type.debugDescription, privacy: .public) - \(subType.debugDescription, privacy: .public) for \(updated.id, privacy: .public)")
        let networtData = await MainActor.run {
            root.gameModel.outgoingMessage(counter: outgoingCounter, type: type, subType: subType, asMaster: false, data: updated)
        }

        let origin: GameMessageOrigin = await root.gameModel.gameType == .proxy ? .proxy : .direct(nil)
        await root.statisticsModel.record(networtData, direction: .outgoing, origin: origin)

        let useOnTypeJournal = useJournal || Self.usesFileJournal(for: networtData)
        await sendOriginating(model: networtData, useJournal: useOnTypeJournal)
    }

    static func usesFileJournal(for model: GameNetworkModel) -> Bool {
        model.usesFileJournal || usesFileJournal(type: model.type, subType: model.subType, data: model.data)
    }

    static func usesFileJournal(for data: NetworkCodableDataType) -> Bool {
        data.usesFileJournal
    }

    static func usesFileJournal(type: RPGMessageType, subType: RPGMessageActionType, data: NetworkCodableDataType) -> Bool {
        type == .update && subType == .generic && data.type == .audio && data.data != nil
    }

    static func shouldStartAudioPlayback(isSharePlayActive: Bool, asGameMaster: Bool) -> Bool {
        !isSharePlayActive || asGameMaster
    }
    
    private func sendOriginating(model: GameNetworkModel, useJournal: Bool = false) async {
        if await root.gameModel.gameType == .proxy {
            await root.networkProxyStore.sendMaster(data: model)
        } else {
            await root.networkStore.sendMaster(data: model, fileJournal: useJournal)
            await root.networkProxyStore.sendPlayer(data: model)
        }
    }

    private func sendUpstream(model: GameNetworkModel) async {
        if await root.gameModel.gameType == .proxy {
            await root.networkProxyStore.sendMaster(data: model)
        } else {
            await root.networkStore.sendMaster(data: model, fileJournal: false)
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
            gameModel.sendCharacterTaskId = nil
            gameModel.pendingMapRequests = []
            gameModel.pendingAudioRequests = []
            gameModel.requestedRepairIds = []
            gameModel.requestedFullMapIds = []
            gameModel.resetMasterStateSequence()
            gameModel.resetPresentationSequence()
            gameModel.resetMapContentSequence()
        }
        await gameModel.reset(lostMaster: true)
        await gameModel.reset(sendPlayer: false)
    }
    
    func ready() async {
        Logger.networking.debug("PlayerController: Ready")
        await gameModel.reset(lostMaster: false)
        await sendAudioList()
        await scheduleSendCharacter()
    }
    
    func receivedFile(_ model: GameNetworkModel) async {
        Logger.networking.debug("PlayerController: FILE Received \(model.counter, privacy: .public): \(model.type.debugDescription, privacy: .public) - \(model.subType.debugDescription, privacy: .public), \(model.data.type.token, privacy: .public) id: \(model.data.id, privacy: .public)")
        guard await root.gameModel.gameConfig.isMaster != model.sender.isMaster else { return }
        await receivedProcess(model, origin: .file)
    }
    
    func received(_ model: GameNetworkModel) async {
        await receivedProcess(model, fromProxy: false)
    }

    func receivedSharePlay(_ model: GameNetworkModel, participantId: UUID) async {
        await receivedProcess(model, origin: .sharePlay(participantId))
    }

    func receivedSharePlayFile(_ model: GameNetworkModel) async {
        guard await root.gameModel.gameConfig.isMaster != model.sender.isMaster else { return }
        await receivedProcess(model, origin: .file)
    }

    func sharePlayFileLoadFailed(_ model: GameNetworkModel) async {
        guard model.sender.isMaster,
              await !root.gameModel.gameConfig.isMaster
        else { return }

        if model.type == .reveal {
            // A reveal reference may be fully satisfied by an exact-version
            // local item. The regular handler ACKs that case and requests bytes
            // only when the item or its backing file is unavailable.
            await receivedProcess(model, origin: .file)
            return
        }

        // Metadata-only stores and journaled updates do not consistently ask
        // for missing bytes. Convert the recovery into a store request; the
        // master rebuilds the full module payload and targets its reply here.
        var requestTrigger = model
        requestTrigger.type = .store
        requestTrigger.subType = .store
        let request = await response(for: requestTrigger, isSuccess: true, requestData: true)
        await sendUpstream(model: request)
    }
    
    func receivedProcess(_ model: GameNetworkModel, fromProxy: Bool = false) async {
        Logger.networking.debug("PlayerController: Received \(model.counter, privacy: .public): \(model.type.debugDescription, privacy: .public) - \(model.subType.debugDescription, privacy: .public), \(model.data.type.token, privacy: .public) id: \(model.data.id, privacy: .public)")

        let origin: GameMessageOrigin = fromProxy ? .proxy : .direct(nil)
        await receivedProcess(model, origin: origin)
    }

    private func receivedProcess(_ model: GameNetworkModel, origin: GameMessageOrigin) async {
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
            if !event.fromProxy, !model.isAcknowledgement {
                await root.networkProxyStore.sendPlayer(data: model)
            }
            Logger.networking.debug("PlayerController: Message ignored, targeted at \(targetId, privacy: .public)")
            return false
        }

        if await !gameModel.asGameMaster {
            let controls = model.masterState?.controls ?? []
            if let masterState = model.masterState,
               model.sender.isMaster,
               await gameModel.shouldApplyMasterState(from: model.masterId, counter: model.counter) {
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

        if model.isPresentationIntent || model.isMapPresentationRepair {
            let shouldProcess = await gameModel.shouldProcessPresentation(
                from: model.masterId,
                module: model.data.type,
                itemId: model.data.id,
                version: model.data.version,
                counter: model.counter,
                isRepair: model.targetId != nil || model.isMapPresentationRepair,
                allowsUnversionedStateRepair: model.isTargetedMapStatePresentationRepair
            )
            guard shouldProcess else {
                Logger.networking.debug("PlayerController: Stale presentation ignored \(model.counter, privacy: .public), \(model.data.type.token, privacy: .public) id: \(model.data.id, privacy: .public)")
                return false
            }
        }

        if !event.fromProxy, !model.isAcknowledgement {
            // Proxy clients mirror this player: an answer addressed to this
            // device must be processed by them too, so clear the target before
            // forwarding. (Messages targeted at OTHERS were already forwarded
            // above and never reach this point.)
            var forwarded = model
            if await forwarded.targetId == root.gameModel.gameConfig.id {
                forwarded.targetId = nil
            }
            await root.networkProxyStore.sendPlayer(data: forwarded)
            await scheduleSendCharacter()
        }
        return true
    }
    
    func processMessages() async {
        while let event = await messagePipeline.next() {
            guard await prepareForProcessing(event) else {
                await messagePipeline.processed(success: true)
                continue
            }

            do {
                try Task.checkCancellation()
                let response = try await handle(
                    event.model,
                    usesSharePlayPlaybackCoordination: event.origin.usesSharePlayFileTransport
                )
                try Task.checkCancellation()
                if let response {
                    await sendUpstream(model: response)
                    if response.subType == .ok {
                        await gameModel.increaseMessageCounter()
                    }
                } else {
                    await gameModel.increaseMessageCounter()
                }
                await root.statisticsModel.record(
                    event.model,
                    direction: .incoming,
                    origin: event.origin
                )
                await messagePipeline.processed(success: true)
            } catch is CancellationError {
                await messagePipeline.processed(success: false)
                return
            } catch {
                Logger.networking.error("PlayerController: Failed to process \(event.model.debugDescription, privacy: .public): \(error.localizedDescription, privacy: .public)")
                let failure = await response(for: event.model, isSuccess: false, requestData: false)
                await sendUpstream(model: failure)
                await messagePipeline.processed(success: false)
            }
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
        await sendAudioList()
        await scheduleSendCharacter()
    }
    
    func receivedProxy(_ model: GameNetworkModel) async {
        Logger.networking.debug("PlayerController: Proxy Received \(model.counter, privacy: .public) / \(model.proxyCounter, privacy: .public): \(model.type.debugDescription, privacy: .public) - \(model.subType.debugDescription, privacy: .public), \(model.data.type.token, privacy: .public) id: \(model.data.id, privacy: .public)")
        await receivedProcess(model, fromProxy: true)
    }
}

extension PlayerController {
    func handle(
        _ model: GameNetworkModel,
        usesSharePlayPlaybackCoordination: Bool = false
    ) async throws -> GameNetworkModel? {
        switch model.data.type {
        case .none, .game, .setting, .editor, .generator, .search:
            return nil
        case .adventure:
            return handleAdventure(model)
        case .audio:
            return try await handleAudio(
                model,
                usesSharePlayPlaybackCoordination: usesSharePlayPlaybackCoordination
            )
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
    
    func handleAudio(
        _ model: GameNetworkModel,
        usesSharePlayPlaybackCoordination: Bool = false
    ) async throws -> GameNetworkModel? {
        if model.subType == .ok {
            await root.audioRoot.gameControllable.report(itemId: model.data.id, for: model.sender.id)
            return nil
        }
        guard model.subType != .failed else { return nil }
        
        switch model.type {
        case .reveal:
            let revealed = try await root.audioRoot.gameControllable.reveal(itemId: model.data.id, data: model.data, save: true)
            if revealed, await root.audioRoot.audioGameControllable.hasLocalAudioData(for: model.data.id) {
                await MainActor.run { _ = gameModel.pendingAudioRequests.remove(model.data.id) }
                await root.audioRoot.audioGameControllable.applyAudio(id: model.data.id, for: [root.gameModel.gameConfig.id, model.sender.id])
                return await response(for: model, isSuccess: true, requestData: false)
            } else {
                await MainActor.run { _ = gameModel.pendingAudioRequests.insert(model.data.id) }
                return await response(for: model, isSuccess: true, requestData: true)
            }
        case .store:
            try await root.audioRoot.gameControllable.updateGame(data: model.data, hide: model.subType == .store, deep: true)
            guard await root.audioRoot.audioGameControllable.hasLocalAudioData(for: model.data.id) else {
                await MainActor.run { _ = gameModel.pendingAudioRequests.insert(model.data.id) }
                return await response(for: model, isSuccess: true, requestData: true)
            }
            let completesReveal = await MainActor.run { gameModel.pendingAudioRequests.remove(model.data.id) != nil }
            if completesReveal {
                _ = await root.audioRoot.gameControllable.setCurrent(itemId: model.data.id)
            }
            await root.audioRoot.audioGameControllable.applyAudio(id: model.data.id, for: [root.gameModel.gameConfig.id, model.sender.id])
            return await response(for: model, isSuccess: true, requestData: false)
        case .update:
            switch model.subType {
            case .audioList:
                await root.audioRoot.audioGameControllable.applyAudioList(data: model.data, for: model.sender.id, authoritative: model.sender.isMaster)
            case .playAudio:
                guard model.sender.isMaster else { return nil }
                await root.audioRoot.audioGameControllable.applyAudio(id: model.data.id, for: (model.masterState?.controls.map { $0.id } ?? []) + [model.masterId])
                let asGameMaster = await gameModel.asGameMaster
                if Self.shouldStartAudioPlayback(
                    isSharePlayActive: usesSharePlayPlaybackCoordination,
                    asGameMaster: asGameMaster
                ) {
                    let _ = await root.audioRoot.audioGameControllable.play(with: model.data).result
                } else {
                    // The master device initiates playback; other SharePlay
                    // participants only prepare for AVPlayerPlaybackCoordinator.
                    await root.audioRoot.audioGameControllable.loadPlaylist(id: model.data.id)
                }
            default:
                break
            }
        }
        return nil
    }

    func handleDice(_ model: GameNetworkModel) async throws -> GameNetworkModel? {
        let features = await root.gameModel.gameControl.features
        guard await (root.gameModel.gameConfig.id != model.sender.id) &&
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
            let hasBaseMap = await root.mapRoot.gameControllable.hasItem(
                id: model.data.id,
                version: 0
            )
            let hasMatchingAsset: Bool
            if hasBaseMap, model.data.assetVersion != nil {
                hasMatchingAsset = await hasMatchingMapAsset(model.data)
            } else {
                hasMatchingAsset = false
            }
            let shouldImportFullPayload: Bool
            if model.data.data == nil {
                shouldImportFullPayload = true
            } else {
                shouldImportFullPayload = await gameModel.shouldImportFullMapContent(
                    itemId: model.data.id,
                    counter: model.counter
                )
            }
            let revealed: Bool
            if model.data.data != nil, model.data.assetVersion != nil {
                if hasBaseMap, !shouldImportFullPayload {
                    // A newer full/photo-free update already won. Keep its
                    // metadata while honoring this reveal as a request to show.
                    _ = await root.mapRoot.gameControllable.setCurrent(itemId: model.data.id)
                } else {
                    // Current-protocol full payloads carry independent asset and
                    // content fingerprints. Always import a newly sequenced one:
                    // the background may have changed without the legacy scale
                    // version changing, or its structural snapshot may be newer
                    // even though the background still matches.
                    try await root.mapRoot.gameControllable.updateGame(
                        data: model.data,
                        hide: true,
                        deep: false
                    )
                }
                revealed = true
            } else if model.data.data == nil, model.data.assetVersion != nil {
                // Mutable map metadata may have changed while the background
                // asset stayed the same. Current peers can reuse that asset and
                // wait for the companion mapUpdate; legacy peers still follow
                // the original scale-version comparison in reveal().
                if hasMatchingAsset {
                    _ = await root.mapRoot.gameControllable.setCurrent(itemId: model.data.id)
                }
                // A reference for a different background asset must request the
                // full Journal/messenger package even when the legacy scale-only
                // `version` still matches the local MapModel.
                revealed = hasMatchingAsset
            } else {
                revealed = try await root.mapRoot.gameControllable.reveal(
                    itemId: model.data.id,
                    data: model.data,
                    save: false
                )
            }

            if revealed {
                // A map without its background photo is incomplete — ask for the
                // whole package once instead of putting the background onto the
                // pin-photo repair path. The single retry bounds payload loops.
                if await !root.mapRoot.mapGameControllable.hasBackgroundImage(itemId: model.data.id) {
                    let isFirstFullMapRequest = await MainActor.run { gameModel.requestedFullMapIds.insert(model.data.id).inserted }
                    if isFirstFullMapRequest {
                        return await response(for: model, isSuccess: true, requestData: true)
                    }
                }
                _ = await root.mapRoot.gameControllable.setCurrent(itemId: model.data.id)
                if model.data.data != nil {
                    await gameModel.recordFullMapContentVersion(
                        itemId: model.data.id,
                        contentVersion: model.data.contentVersion,
                        counter: model.counter
                    )
                }
                _ = await applyPendingMapContentUpdate(itemId: model.data.id)
                await MainActor.run {
                    // Also for players: a reveal means "show the map". Waiting for
                    // the next mapState left the screen behind the black overlay
                    // when that one-shot message was missed.
                    gameModel.gameUpdateType = .map
                }
                // Also on a re-reveal from memory: a newer mapState may have
                // introduced a pin whose photo model is not owned locally.
                // `requestedRepairIds` keeps this to one request per connection.
                await requestMissingMapImages(itemId: model.data.id)
                #if os(visionOS)
                // A re-reveal of the current map changes rooms/pins without a
                // map change — bring the 3D table up to date as well.
                let isGameMaster = await root.gameModel.gameConfig.isMaster
                await root.gameModel.gameTableModel?.updateFogOfWar(isGameMaster: isGameMaster)
                await MainActor.run {
                    root.gameModel.gameTableModel?.syncPawnsWithMapPins()
                }
                #endif
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
            let completesReveal = await MainActor.run { gameModel.pendingMapRequests.remove(model.data.id) != nil }
            try await root.mapRoot.gameControllable.updateGame(data: model.data, hide: true, deep: true)
            await gameModel.recordFullMapContentVersion(
                itemId: model.data.id,
                contentVersion: model.data.contentVersion,
                counter: model.counter
            )
            _ = await applyPendingMapContentUpdate(itemId: model.data.id)
            if completesReveal {
                // The payload answers a mapState-triggered re-request: the map is
                // the current presentation, and the mapState that flips the screen
                // was sent alongside — usually arriving before this big payload.
                _ = await root.mapRoot.gameControllable.setCurrent(itemId: model.data.id)
                await MainActor.run {
                    gameModel.gameUpdateType = .map
                }
                await requestMissingMapImages(itemId: model.data.id)
                #if os(visionOS)
                let isGameMaster = await root.gameModel.gameConfig.isMaster
                await root.gameModel.gameTableModel?.updateFogOfWar(isGameMaster: isGameMaster)
                await MainActor.run {
                    root.gameModel.gameTableModel?.syncPawnsWithMapPins()
                }
                #endif
            }
            return await response(for: model, isSuccess: true, requestData: false)
        case .update:
            switch model.subType {
            case .generic:
                return await handleMapContentUpdate(model)
            case .mapState:
                if await root.mapRoot.gameControllable.hasItem(id: model.data.id, version: 0) {
                    await root.mapRoot.mapGameControllable.updateMap(for: model.data.id, with: model.data)
                    // mapState carries pin metadata but not newly referenced
                    // photo models. Repair missing pin photos through the normal
                    // data-less `.store` request. The background stays with map.
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

    func handleMapContentUpdate(_ model: GameNetworkModel) async -> GameNetworkModel? {
        guard model.sender.isMaster, model.data.data != nil else { return nil }
        guard await gameModel.shouldApplyMapContentUpdate(
            itemId: model.data.id,
            counter: model.counter
        ) else { return nil }

        let hasBaseMap = await root.mapRoot.gameControllable.hasItem(id: model.data.id, version: 0)
        let hasMatchingAsset = await hasMatchingMapAsset(model.data)
        guard hasBaseMap, hasMatchingAsset else {
            await gameModel.queueMapContentUpdate(model.data, counter: model.counter)
            let isFirstRequest = await MainActor.run {
                gameModel.pendingMapRequests.insert(model.data.id).inserted
            }
            guard isFirstRequest else { return nil }
            return await MainActor.run {
                root.gameModel.outgoingMessage(
                    counter: model.counter,
                    proxyCounter: model.proxyCounter,
                    type: .reveal,
                    subType: .mapState,
                    asMaster: false,
                    data: NetworkCodableDataType(
                        id: model.data.id,
                        type: .map,
                        version: model.data.version,
                        data: nil,
                        assetVersion: model.data.assetVersion,
                        contentVersion: model.data.contentVersion
                    )
                )
            }
        }

        guard await root.mapRoot.mapGameControllable.applyMapContentUpdate(
            for: model.data.id,
            with: model.data
        ) else { return nil }
        await gameModel.markMapContentUpdateApplied(
            itemId: model.data.id,
            counter: model.counter,
            contentVersion: model.data.contentVersion
        )
        await requestMissingMapImages(itemId: model.data.id)

        #if os(visionOS)
        let isGameMaster = await root.gameModel.gameConfig.isMaster
        await root.gameModel.gameTableModel?.updateFogOfWar(isGameMaster: isGameMaster)
        await MainActor.run {
            root.gameModel.gameTableModel?.syncPawnsWithMapPins()
        }
        #endif
        return nil
    }

    func applyPendingMapContentUpdate(itemId: UUID) async -> Bool {
        guard let pending = await gameModel.pendingMapContentUpdate(for: itemId) else { return false }
        guard await gameModel.shouldApplyMapContentUpdate(
            itemId: itemId,
            counter: pending.counter
        ) else {
            await gameModel.discardPendingMapContentUpdate(itemId: itemId)
            return false
        }
        guard await root.mapRoot.gameControllable.hasItem(id: itemId, version: 0),
              await hasMatchingMapAsset(pending.data),
              await root.mapRoot.mapGameControllable.applyMapContentUpdate(
                for: itemId,
                with: pending.data
              )
        else { return false }

        await gameModel.markMapContentUpdateApplied(
            itemId: itemId,
            counter: pending.counter,
            contentVersion: pending.data.contentVersion
        )
        return true
    }

    func hasMatchingMapAsset(_ data: NetworkCodableDataType) async -> Bool {
        guard let expectedAssetVersion = data.assetVersion else { return true }
        return await root.mapRoot.mapGameControllable.mapAssetVersion(for: data.id) == expectedAssetVersion
    }

    /// Requests pin photos absent from both the photo game state and persistent
    /// item controller. The map background is delivered with the full map.
    /// Each photo is requested once per connection; SharePlay turns the first
    /// full answer into one group store so peers do not transfer it again.
    func requestMissingMapImages(itemId: UUID) async {
        let missingImages = await root.mapRoot.mapGameControllable.missingMapImages(itemId: itemId)
        for idType in missingImages {
            let isFirstRequest = await MainActor.run { gameModel.requestedRepairIds.insert(idType.id).inserted }
            guard isFirstRequest else { continue }
            await send(type: .store, subType: .store, updated: idType)
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
                let hasLocalData = await root.pdfRoot.gameControllable.hasLocalFileData(for: model.data.id)
                return await response(for: model, isSuccess: hasLocalData, requestData: !hasLocalData)
            case .update:
                break
        }
        return nil
    }

    func handlePhoto(_ model: GameNetworkModel) async throws -> GameNetworkModel? {
        // Player-originated reveal/update messages are requests relayed through
        // SharePlay or a proxy, not presentation commands for this device.
        guard model.sender.isMaster || model.type == .store else { return nil }

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
            let hasLocalData = await root.photoRoot.gameControllable.hasLocalFileData(for: model.data.id)
            if hasLocalData {
                await MainActor.run { _ = gameModel.requestedRepairIds.remove(model.data.id) }
            }
            return await response(for: model, isSuccess: hasLocalData, requestData: !hasLocalData)
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
            let hasLocalData = await root.spaceRoot.gameControllable.hasLocalFileData(for: model.data.id)
            return await response(for: model, isSuccess: hasLocalData, requestData: !hasLocalData)
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
        // A "please send more" request only needs to name the item: the master
        // rebuilds the payload from `data.id` via createGameData and never reads
        // these bytes. Echoing `model.data` verbatim used to re-upload whatever
        // we just received — e.g. a map that's merely short its background photo
        // sent its whole multi-MB self straight back upstream over the slow,
        // small-message-oriented player→master path, for nothing.
        let payload = NetworkCodableDataType(id: model.data.id, type: model.data.type, version: requestData ? model.data.version : 0, data: nil)
        // Echo the counter of the message being answered (same precedent as the
        // mapState re-request below) instead of minting a fresh one. The pipeline
        // already deduplicates the incoming trigger, so this stays exactly-once;
        // it also lets the master's message log match the ack back to the row it
        // created for the original send — with a fresh counter here that link
        // was counter-space garbage and the log's delivery indicator could never
        // leave "missing players", on every transport, not just file sharing.
        return await MainActor.run {
            root.gameModel.outgoingMessage(counter: model.counter, proxyCounter: model.proxyCounter, type: model.type, subType: subType, asMaster: false, data: payload)
        }
    }

    func scheduleSendCharacter() async {
        await MainActor.run {
            guard gameModel.sendCharacterTask == nil else { return }
            let taskId = UUID()
            gameModel.sendCharacterTaskId = taskId
            gameModel.sendCharacterTask = Task { [weak self] in
                await self?.sendCharacter()
                await MainActor.run {
                    guard self?.gameModel.sendCharacterTaskId == taskId else { return }
                    self?.gameModel.sendCharacterTask = nil
                    self?.gameModel.sendCharacterTaskId = nil
                }
            }
        }
    }

    func scheduleProxyFocus(characterId: UUID) async {
        await MainActor.run {
            gameModel.proxyFocusTask?.cancel()
            let taskId = UUID()
            gameModel.proxyFocusTaskId = taskId
            gameModel.proxyFocusTask = Task { [weak self] in
                guard let self else { return }
                _ = await root.characterRoot.gameControllable.setCurrent(itemId: characterId)
                await root.characterRoot.gameControllable.focus(on: characterId)
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    await MainActor.run {
                        guard self.gameModel.proxyFocusTaskId == taskId else { return }
                        self.gameModel.proxyFocusTask = nil
                        self.gameModel.proxyFocusTaskId = nil
                    }
                    return
                }
                guard !Task.isCancelled else {
                    await MainActor.run {
                        guard self.gameModel.proxyFocusTaskId == taskId else { return }
                        self.gameModel.proxyFocusTask = nil
                        self.gameModel.proxyFocusTaskId = nil
                    }
                    return
                }
                await MainActor.run {
                    guard gameModel.proxyFocusTaskId == taskId else { return }
                    root.gameModel.selectedCharacter = characterId
                    gameModel.proxyFocusTask = nil
                    gameModel.proxyFocusTaskId = nil
                }
            }
        }
    }
    
    func sendCharacter() async {
        let gameType = await root.gameModel.gameType
        let canSend = await MainActor.run { !gameModel.hasSendPlayer && !gameModel.lostMaster }
        // A proxy device never announces a character: it mirrors the host
        // player and receives the host's character on readyProxy instead.
        guard canSend, gameType != .observer, gameType != .proxy,
              let characterId = await root.gameModel.gamePlayer.characterId
        else { return }

        do {
            try Task.checkCancellation()
            let result = try await root.characterRoot.gameControllable.createGameData(for: characterId)
            try Task.checkCancellation()
            await send(type: .update, subType: .store, updated: result, useJournal: true)
            let lostMaster = await gameModel.lostMaster
            guard !Task.isCancelled, !lostMaster else { return }
            await gameModel.reset(sendPlayer: true)
        } catch is CancellationError {
            return
        } catch {
            Logger.networking.error("PlayerController: Failed to send character \(characterId, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    func sendAudioList() async {
        // A proxy device stays invisible: the host answers for its audio
        // availability, and the host consumes any list that still arrives.
        guard await root.gameModel.gameType != .proxy else { return }
        let audioList = await root.audioRoot.audioGameControllable.audioList(allPlayers: false, with: root.gameModel.gameConfig.id)
        await send(type: .update, subType: .audioList, updated: audioList, useJournal: false)
    }
}
