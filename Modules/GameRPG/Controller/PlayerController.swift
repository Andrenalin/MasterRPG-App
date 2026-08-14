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

@MainActor
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
    func start(to model: BrowserGameModel?, joinCode: String = "") async -> Bool {
        Logger.networking.debug("PlayerController: Start")
        // Observers are a read-only local-network role. Do not let a nil Bonjour
        // target silently turn an observer into a SharePlay participant.
        if root.gameModel.gameType == .observer, model == nil {
            return false
        }
        if root.gameModel.gameType == .player {
            // This device also relays for further players — its own stored
            // Player code, not the code just entered to join the master.
            root.networkProxyStore.startProxyServer(passcode: root.gameJoinCodeModel.playerCode)
        } else if root.gameModel.gameType == .proxy {
            return await root.networkProxyStore.startPlayerGame(to: model, passcode: joinCode)
        }
        return await root.networkStore.startPlayerGame(to: model, passcode: joinCode)
    }

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
        gameModel.requestedPdfRepairIds = []
        gameModel.requestedSpaceRepairIds = []
        gameModel.resetMasterStateSequence()
        gameModel.resetAudioListSequence()
        gameModel.resetPhotoListSequence()
        gameModel.resetPdfListSequence()
        gameModel.resetSpaceListSequence()
        gameModel.resetPresentationSequence()
        gameModel.resetMapContentSequence()
        gameModel.resetSharePlayMasterParticipant()
    }

    /// Combines `GameRootModel.applyMasterBroadcast` with `resetPlayers()` in one
    /// @MainActor call so both happen atomically — see CODE_AUDIT §3.1.
    func applyMasterBroadcastAndResetPlayers(
        masterId: UUID,
        masterName: String,
        supporterTier: SupporterTier,
        state: GameMasterStateModel
    ) {
        root.gameModel.applyMasterBroadcast(
            masterId: masterId,
            masterName: masterName,
            supporterTier: supporterTier,
            state: state
        )
        resetPlayers()
    }

    /// Spans two separate @MainActor models (`gameModel` and `root.gameModel`), so
    /// it lives on the controller rather than either model — one @MainActor call
    /// keeps both updates atomic. See CODE_AUDIT §3.1.
    func setMapUpdateTypeAndSyncPawns() {
        gameModel.setGameUpdateType(.map)
        #if !os(tvOS)
        root.gameModel.gameTableModel?.syncPawnsWithMapPins()
        #endif
    }

    /// Clears the space repair-pending flag, marks the space update, and (on
    /// visionOS) switches to immersive presentation. Spans two @MainActor
    /// models (`gameModel` and `root.gameModel`), so it lives on the
    /// controller — one @MainActor call keeps all three updates atomic.
    /// See CODE_AUDIT §3.1.
    func completeSpaceReveal(itemId: UUID) {
        gameModel.requestedSpaceRepairIds.remove(itemId)
        gameModel.setGameUpdateType(.space)
        #if os(visionOS)
        if root.networkStore.sharePlayStore.isActive {
            root.gameModel.shareState.mode = .immersive
        }
        #endif
    }

    func resetPlayers() {
        let players = root.gameModel.gameControl.controls.compactMap { $0.show ? $0.id : nil }
        root.audioRoot.gameControllable.gameModel.currentPlayers = (players + [root.gameModel.gameConfig.master.id]).sorted()
        root.photoRoot.gameControllable.gameModel.currentPlayers = (players + [root.gameModel.gameConfig.master.id]).sorted()
        root.pdfRoot.gameControllable.gameModel.currentPlayers = (players + [root.gameModel.gameConfig.master.id]).sorted()
        root.spaceRoot.gameControllable.gameModel.currentPlayers = (players + [root.gameModel.gameConfig.master.id]).sorted()
        root.tableRoot.gameControllable.gameModel.currentPlayers = (players + [root.gameModel.gameConfig.master.id]).sorted()
        root.weatherRoot.gameControllable.gameModel.currentPlayers = (players + [root.gameModel.gameConfig.master.id]).sorted()
        let playerNames = root.gameModel.gameControl.controls.map { $0.name }.sorted()
        root.diceRoot.diceGameControllable.resetPlayerDice(to: [root.gameModel.gameConfig.master.name] + playerNames)
    }
}

// MARK: - Send Messages

extension PlayerController {
    func send(updated: NetworkCodableDataType) async {
        guard root.gameModel.gameType != .observer else { return }
        guard updated.type != .value else { return }
        await send(type: .store, subType: .store, updated: updated)
    }

    func game(message: NetworkCodableDataType, actionType: RPGMessageActionType) async {
        guard root.gameModel.gameType != .observer else { return }
        // Players cannot publish Weather and Weather has no live updates yet.
        guard message.type != .table, message.type != .weather else { return }
        if message.type == .value {
            let playerCharacterId = root.gameModel.gamePlayer.characterId
            guard actionType == .valueUpdate,
                  message.data != nil,
                  message.id == playerCharacterId else {
                return
            }
            // Value updates are small causal events and deliberately stay on
            // Messenger/chunked transports, never GroupSessionJournal.
            await send(
                type: .update,
                subType: .valueUpdate,
                updated: message,
                useJournal: false
            )
            return
        }
        if message.type == .photo, actionType == .generic {
            guard root.gameModel.gameControl.features.photoSharing else { return }
            await sharePhoto(message)
            return
        }
        if message.type == .pdf, actionType == .generic {
            await sharePdf(message)
            return
        }
        if message.type == .space, actionType == .generic {
            await shareSpace(message)
            return
        }
        if message.type == .space, actionType == .spaceTransform {
            guard root.gameModel.gameControl.features.spaceSharing else { return }
        }
        if message.type == .audio {
            guard root.gameModel.gameControl.features.audioSharing else { return }
        }
        if message.type == .dice {
            guard root.gameModel.gameControl.features.dicePlayers else { return }
        }
        await send(type: .update, subType: actionType, updated: message)
    }

    private func sharePhoto(_ fullData: NetworkCodableDataType) async {
        let (playerId, masterId) = await MainActor.run {
            (root.gameModel.gameConfig.id, root.gameModel.gameConfig.master.id)
        }
        let baseline = root.photoRoot.photoGameControllable.masterVersion(
            for: fullData.id,
            masterId: masterId
        )
        let senderIsAvailable = root.photoRoot.photoGameControllable.isPhotoAvailable(
            itemId: fullData.id,
            for: playerId,
            masterId: masterId
        )
        let matchesBaseline = baseline == fullData.effectiveAssetVersion

        let outgoing: NetworkCodableDataType
        if senderIsAvailable, matchesBaseline {
            let allPlayersHavePhoto = root.photoRoot.gameControllable.allPlayersReported(for: fullData.id)
            outgoing = NetworkCodableDataType(
                id: fullData.id,
                type: fullData.type,
                version: fullData.version,
                data: allPlayersHavePhoto ? nil : fullData.data,
                assetVersion: fullData.assetVersion,
                contentVersion: fullData.contentVersion
            )
            if await root.photoRoot.gameControllable.setCurrent(itemId: fullData.id) {
                gameModel.setGameUpdateType(.photo)
            }
        } else if baseline == nil {
            // The master has no copy at all — unlike a mismatched/competing
            // edit of an item the master already owns, there is no canonical
            // baseline to defer to. Attach the full bytes so the master can
            // adopt them as its own copy (mirrors MasterController.handlePhoto's
            // `.itemMissing` import fallback, which otherwise has nothing to
            // import and silently drops the reveal).
            outgoing = fullData
        } else {
            // The master owns the canonical version. A player whose report is
            // absent or mismatched sends only that baseline reference; the
            // master answers by publishing its own bytes.
            outgoing = NetworkCodableDataType(
                id: fullData.id,
                type: fullData.type,
                version: baseline ?? fullData.effectiveAssetVersion
            )
        }

        await send(type: .reveal, subType: .show, updated: outgoing)

        if senderIsAvailable, matchesBaseline, outgoing.data != nil, let baseline {
            root.photoRoot.photoGameControllable.markPhotoAvailableToCurrentPlayers(
                itemId: fullData.id,
                version: baseline,
                masterId: masterId
            )
        }
    }

    private func sharePdf(_ fullData: NetworkCodableDataType) async {
        let (playerId, masterId) = await MainActor.run {
            (root.gameModel.gameConfig.id, root.gameModel.gameConfig.master.id)
        }
        let baseline = root.pdfRoot.pdfGameControllable.masterVersion(
            for: fullData.id,
            masterId: masterId
        )
        let senderIsAvailable = root.pdfRoot.pdfGameControllable.isPdfAvailable(
            itemId: fullData.id,
            for: playerId,
            masterId: masterId
        )
        let matchesBaseline = baseline == fullData.effectiveAssetVersion

        let outgoing: NetworkCodableDataType
        if senderIsAvailable, matchesBaseline {
            let allPlayersHavePdf = root.pdfRoot.gameControllable.allPlayersReported(for: fullData.id)
            outgoing = NetworkCodableDataType(
                id: fullData.id,
                type: fullData.type,
                version: fullData.version,
                data: allPlayersHavePdf ? nil : fullData.data,
                assetVersion: fullData.assetVersion,
                contentVersion: fullData.contentVersion
            )
            if await root.pdfRoot.gameControllable.setCurrent(itemId: fullData.id) {
                gameModel.setGameUpdateType(.pdf)
            }
        } else if baseline == nil {
            // The master has no copy at all — unlike a mismatched/competing
            // edit of an item the master already owns, there is no canonical
            // baseline to defer to. Attach the full bytes so the master can
            // adopt them as its own copy (mirrors MasterController.handlePdf's
            // `.itemMissing` import fallback, which otherwise has nothing to
            // import and silently drops the reveal).
            outgoing = fullData
        } else {
            // The game master's file/version is canonical. A missing or stale
            // player report is a request for that asset, never an upload.
            outgoing = NetworkCodableDataType(
                id: fullData.id,
                type: fullData.type,
                version: baseline ?? fullData.effectiveAssetVersion
            )
        }

        await send(type: .reveal, subType: .show, updated: outgoing)

        if senderIsAvailable, matchesBaseline, outgoing.data != nil, let baseline {
            root.pdfRoot.pdfGameControllable.markPdfAvailableToCurrentPlayers(
                itemId: fullData.id,
                version: baseline,
                masterId: masterId
            )
        }
    }

    private func shareSpace(_ fullData: NetworkCodableDataType) async {
        guard root.gameModel.gameControl.features.spaceSharing else { return }
        let (playerId, masterId) = await MainActor.run {
            (root.gameModel.gameConfig.id, root.gameModel.gameConfig.master.id)
        }
        let baseline = root.spaceRoot.spaceGameControllable.masterVersion(
            for: fullData.id,
            masterId: masterId
        )
        let senderIsAvailable = root.spaceRoot.spaceGameControllable.isSpaceAvailable(
            itemId: fullData.id,
            for: playerId,
            masterId: masterId
        )
        let matchesBaseline = baseline == fullData.effectiveAssetVersion

        let outgoing: NetworkCodableDataType
        if senderIsAvailable, matchesBaseline {
            let allPlayersHaveSpace = root.spaceRoot.gameControllable.allPlayersReported(for: fullData.id)
            outgoing = NetworkCodableDataType(
                id: fullData.id,
                type: fullData.type,
                version: fullData.version,
                data: allPlayersHaveSpace ? nil : fullData.data,
                assetVersion: fullData.assetVersion,
                contentVersion: fullData.contentVersion
            )
            if await root.spaceRoot.gameControllable.setCurrent(itemId: fullData.id) {
                gameModel.setGameUpdateType(.space)
            }
        } else if baseline == nil {
            // The master has no copy at all — unlike a mismatched/competing
            // edit of an item the master already owns, there is no canonical
            // baseline to defer to. Attach the full bytes so the master can
            // adopt them as its own copy (mirrors MasterController.handleSpace's
            // `.itemMissing` import fallback, which otherwise has nothing to
            // import and silently drops the reveal).
            outgoing = fullData
        } else {
            // A peer never establishes a competing baseline. A missing or stale
            // report becomes a request for the game master's canonical asset.
            outgoing = NetworkCodableDataType(
                id: fullData.id,
                type: fullData.type,
                version: baseline ?? fullData.effectiveAssetVersion
            )
        }

        await send(type: .reveal, subType: .show, updated: outgoing)

        if senderIsAvailable, matchesBaseline, outgoing.data != nil, let baseline {
            root.spaceRoot.spaceGameControllable.markSpaceAvailableToCurrentPlayers(
                itemId: fullData.id,
                version: baseline,
                masterId: masterId
            )
        }
    }

    func send(
        counter: Int? = nil,
        type: RPGMessageType,
        subType: RPGMessageActionType = .show,
        updated: NetworkCodableDataType,
        useJournal: Bool = false,
        relayToProxyClients: Bool = true,
        purpose: GameMessagePurpose = .event
    ) async {
        // Tables have no live-update protocol. Only reveal/store messages may
        // carry their versioned canonical package.
        guard type != .update || updated.type != .table else { return }

        let outgoingTimestamp: TimeInterval
        if type == .update,
           subType == .spaceTransform,
           updated.type == .space {
            guard let timestamp = root.spaceRoot.spaceGameControllable
                .causalSpaceTransformTimestamp(
                    itemId: updated.id,
                    version: updated.effectiveAssetVersion
                )
            else { return }
            outgoingTimestamp = timestamp
        } else {
            outgoingTimestamp = Date.now.timeIntervalSince1970
        }

        // Both are @MainActor method calls (not property writes) — `await` alone hops,
        // no `MainActor.run` wrapper needed.
        let outgoingCounter: Int
        if let counter {
            outgoingCounter = counter
        } else {
            outgoingCounter = gameModel.nextOutgoingMessageCounter()
        }
        Logger.networking.debug("PlayerController: Send \(outgoingCounter, privacy: .public): \(type.debugDescription, privacy: .public) - \(subType.debugDescription, privacy: .public) for \(updated.id, privacy: .public)")
        let networtData = root.gameModel.outgoingMessage(
            timestamp: outgoingTimestamp,
            counter: outgoingCounter,
            type: type,
            subType: subType,
            asMaster: false,
            purpose: purpose,
            data: updated
        )

        // Group transports do not echo a sender's own event, and the master no
        // longer republishes a canonical Space transform. Apply this exact
        // versioned envelope optimistically so SpaceViewer observes its own
        // timestamped transform as acknowledged and does not retry forever.
        if networtData.purpose == .event,
           networtData.type == .update,
           networtData.subType == .spaceTransform,
           networtData.data.type == .space {
            _ = root.spaceRoot.spaceGameControllable.applySpaceTransform(
                data: networtData.data,
                counter: networtData.counter,
                timestamp: networtData.timestamp
            )
        }

        let origin: GameMessageOrigin = root.gameModel.gameType == .proxy ? .proxy(nil) : .direct(nil)
        await root.statisticsModel.record(networtData, direction: .outgoing, origin: origin)

        let useOnTypeJournal = useJournal || Self.usesFileJournal(for: networtData)
        await sendOriginating(
            model: networtData,
            useJournal: useOnTypeJournal,
            relayToProxyClients: relayToProxyClients
        )
    }

    /// Turns one private mirror's presentation into one canonical host-player
    /// event. The same remapped envelope is used for the upstream send, sibling
    /// mirrors, and the co-located host player so transport retries cannot mint
    /// independent counters or identities for a single user gesture.
    func relayProxyPresentation(
        _ source: GameNetworkModel,
        excludingProxyConnection connectionId: ConnectionController.ID?
    ) async {
        guard source.purpose == .event,
              source.type == .reveal,
              source.subType == .show,
              (source.data.type == .photo || source.data.type == .pdf || source.data.type == .space)
        else { return }

        // Both are @MainActor method calls (not property writes) — `await` alone hops,
        // no `MainActor.run` wrapper needed.
        let outgoingCounter = gameModel.nextOutgoingMessageCounter()
        let remapped = root.gameModel.outgoingMessage(
            timestamp: source.timestamp,
            counter: outgoingCounter,
            type: source.type,
            subType: source.subType,
            asMaster: false,
            purpose: source.purpose,
            data: source.data
        )

        Logger.networking.debug("PlayerController: Relay proxy presentation \(outgoingCounter, privacy: .public) for \(source.data.type.token, privacy: .public) -> \(source.data.id, privacy: .public)")
        await root.statisticsModel.record(remapped, direction: .outgoing, origin: .proxy(connectionId))

        // Upstream exactly once. In particular, local application below must
        // never manufacture an acknowledgement or repair request of its own.
        await root.networkStore.sendMaster(
            data: remapped,
            fileJournal: Self.usesFileJournal(for: remapped)
        )

        // A private mirror cannot establish a new asset generation. Apply the
        // optimistic local presentation only when it matches the authoritative
        // master baseline; otherwise the master's canonical response will drive
        // the host and mirrors in the regular path.
        guard await canApplyRemappedProxyPresentation(remapped) else { return }
        await receivedProcess(remapped, origin: .local)
        if let connectionId {
            await root.networkProxyStore.sendPlayer(data: remapped, except: connectionId)
        } else {
            await root.networkProxyStore.sendPlayer(data: remapped)
        }
    }

    /// Remaps a private mirror's small group event to the host identity once,
    /// then sends that same envelope upstream and to sibling mirrors. The host
    /// controller has already applied the event locally.
    func relayProxyGroupEvent(
        _ source: GameNetworkModel,
        excludingProxyConnection connectionId: ConnectionController.ID?
    ) async {
        let isSupportedEvent = source.isDiceRollEvent ||
            (source.purpose == .event &&
             source.type == .update &&
             ((source.subType == .mapPin && source.data.type == .map) ||
              (source.subType == .spaceTransform && source.data.type == .space)))
        guard isSupportedEvent else { return }

        // Both are @MainActor method calls (not property writes) — `await` alone hops,
        // no `MainActor.run` wrapper needed.
        let outgoingCounter = gameModel.nextOutgoingMessageCounter()
        let remapped = root.gameModel.outgoingMessage(
            timestamp: source.timestamp,
            counter: outgoingCounter,
            type: source.type,
            subType: source.subType,
            asMaster: false,
            purpose: source.purpose,
            data: source.data
        )
        await root.statisticsModel.record(
            remapped,
            direction: .outgoing,
            origin: .proxy(connectionId)
        )
        await root.networkStore.sendMaster(data: remapped, fileJournal: false)
        if let connectionId {
            await root.networkProxyStore.sendPlayer(data: remapped, except: connectionId)
        } else {
            await root.networkProxyStore.sendPlayer(data: remapped)
        }
    }

    private func canApplyRemappedProxyPresentation(_ model: GameNetworkModel) async -> Bool {
        let masterId = root.gameModel.gameConfig.master.id
        let version = model.data.effectiveAssetVersion

        switch model.data.type {
        case .photo:
            guard root.gameModel.gameControl.features.photoSharing else { return false }
            return root.photoRoot.photoGameControllable.masterVersion(
                for: model.data.id,
                masterId: masterId
            ) == version
        case .pdf:
            return root.pdfRoot.pdfGameControllable.masterVersion(
                for: model.data.id,
                masterId: masterId
            ) == version
        case .space:
            guard root.gameModel.gameControl.features.spaceSharing else { return false }
            return root.spaceRoot.spaceGameControllable.masterVersion(
                for: model.data.id,
                masterId: masterId
            ) == version
        default:
            return false
        }
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

    private func sendOriginating(
        model: GameNetworkModel,
        useJournal: Bool = false,
        relayToProxyClients: Bool = true
    ) async {
        if root.gameModel.gameType == .proxy {
            await root.networkProxyStore.sendMaster(data: model)
        } else {
            await root.networkStore.sendMaster(data: model, fileJournal: useJournal)
            if relayToProxyClients, model.effectiveAudience == .group {
                await root.networkProxyStore.sendPlayer(data: model)
            }
        }
    }

    /// Called cross-file by the per-module `retryDeferredXReveals` helpers
    /// (Photo/Pdf/Space), so this stays internal rather than `private`.
    func sendUpstream(model: GameNetworkModel) async {
        if root.gameModel.gameType == .proxy {
            await root.networkProxyStore.sendMaster(data: model)
        } else {
            await root.networkStore.sendMaster(data: model, fileJournal: false)
        }
    }
}

// MARK: - Send PlayerNetworkStoreDelegate

extension PlayerController: PlayerNetworkStoreDelegate {
    func lostConnection() async {
        await resetForLostConnection(preservingSharePlayRebind: false)
    }

    func sharePlayParticipantLeft(id: UUID) async {
        guard await gameModel.removeSharePlayMasterParticipant(id: id) else { return }
        await resetForLostConnection(preservingSharePlayRebind: true)
    }

    private func resetForLostConnection(
        preservingSharePlayRebind: Bool
    ) async {
        Logger.networking.debug("PlayerController: Lost Connection - Reset State")
        gameModel.resetForLostConnection(preservingSharePlayRebind: preservingSharePlayRebind)
        root.spaceRoot.spaceGameControllable.resetSpaceTransforms()
        gameModel.reset(lostMaster: true)
        gameModel.reset(sendPlayer: false)
    }

    func ready() async {
        Logger.networking.debug("PlayerController: Ready")
        await gameModel.reset(lostMaster: false)
        await sendAudioList()
        await sendPhotoList()
        await sendPdfList()
        await sendSpaceList()
        await scheduleSendCharacter()
    }

    func receivedFile(_ model: GameNetworkModel) async {
        Logger.networking.debug("PlayerController: FILE Received \(model.counter, privacy: .public): \(model.type.debugDescription, privacy: .public) - \(model.subType.debugDescription, privacy: .public), \(model.data.type.token, privacy: .public) id: \(model.data.id, privacy: .public)")
        let receivesOppositeRole = await root.gameModel.gameConfig.isMaster != model.sender.isMaster
        // A player-authored file presentation has already been authenticated by
        // GameNetworkController before it reaches this callback. LAN and
        // SharePlay both fan that group event out to sibling players, so equal
        // player roles are expected here; all other same-role file traffic is
        // still rejected.
        guard receivesOppositeRole || model.isPlayerFilePresentationEvent else { return }
        await receivedProcess(model, origin: .file)
    }

    func received(_ model: GameNetworkModel) async {
        await receivedProcess(model, fromProxy: false)
    }

    func receivedSharePlay(_ model: GameNetworkModel, participantId: UUID) async {
        await receivedProcess(model, origin: .sharePlay(participantId))
    }

    func acceptsSharePlayPeerMessage(
        _ model: GameNetworkModel,
        participantId: UUID
    ) async -> Bool {
        guard model.sender.role == .player,
              model.effectiveAudience == .group,
              GameNetworkModel.acceptsEventTimestamp(model.timestamp),
              await acceptsSessionMessage(
                  model,
                  origin: .sharePlay(participantId)
              )
        else { return false }

        // The master-authored roster is the logical identity authority on a
        // player-only device. Validate it before GameNetworkController commits
        // the physical participant binding, preventing an unknown or wrong-role
        // first packet from poisoning that immutable transport identity.
        return await root.gameModel.gameRoster.players.contains {
            $0.id == model.sender.id && $0.type == .player
        }
    }

    func shouldDeferSharePlayPeerGroupEvent(
        _ model: GameNetworkModel,
        participantId: UUID
    ) async -> Bool {
        guard model.isDeferrablePlayerGroupEvent,
              await acceptsSessionMessage(
                  model,
                  origin: .sharePlay(participantId)
              )
        else { return false }

        // An existing non-player roster entry is an authoritative rejection,
        // not an ordering race. Only an entirely absent identity gets one
        // opportunity to wait for the next master roster update.
        return await !root.gameModel.gameRoster.players.contains {
            $0.id == model.sender.id
        }
    }

    func didAcceptSharePlayMasterState(
        _ model: GameNetworkModel,
        participantId: UUID
    ) async -> Bool {
        guard model.sender.isMaster,
              model.sender.id == model.masterId,
              model.masterState != nil,
              await gameModel.isSharePlayMasterParticipant(id: participantId),
              await root.gameModel.gameConfig.master.id == model.masterId
        else { return false }

        return await gameModel.hasAppliedMasterState(
            from: model.masterId,
            counter: model.counter
        )
    }

    func acceptsSharePlayMasterJournalAdmission(
        _ model: GameNetworkModel,
        participantId: UUID
    ) async -> Bool {
        guard model.isMasterJournalAdmissionMetadata else { return false }
        return await acceptsSessionMessage(
            model,
            origin: .sharePlay(participantId)
        )
    }

    func isLocalSharePlayTarget(_ targetId: UUID?) async -> Bool {
        guard let targetId else { return true }
        return await root.gameModel.gameConfig.id == targetId
    }

    func receivedSharePlayFile(_ model: GameNetworkModel) async {
        let receivesOppositeRole = await root.gameModel.gameConfig.isMaster != model.sender.isMaster
        guard receivesOppositeRole || model.isPlayerFilePresentationEvent else { return }
        await receivedProcess(model, origin: .file)
    }

    func isPinnedSharePlayMasterParticipant(id: UUID) async -> Bool {
        await gameModel.isSharePlayMasterParticipant(id: id)
    }

    func sharePlayFileLoadFailed(_ model: GameNetworkModel) async {
        guard model.sender.isMaster,
              await !root.gameModel.gameConfig.isMaster,
              await acceptsSessionMessage(model, origin: .file)
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

        let origin: GameMessageOrigin = fromProxy ? .proxy(nil) : .direct(nil)
        await receivedProcess(model, origin: origin)
    }

    private func receivedProcess(_ model: GameNetworkModel, origin: GameMessageOrigin) async {
        // Admission-only metadata is consumed by GameNetworkController after
        // physical SharePlay attribution. It is never a gameplay message.
        guard !model.isJournalAdmissionOnly else { return }
        guard await acceptsSessionMessage(model, origin: origin) else {
            Logger.networking.debug("PlayerController: Message rejected because its sender does not belong to this game session")
            return
        }
        guard await messagePipeline.enqueue(GameMessageEvent(model: model, origin: origin)) else {
            Logger.networking.debug("PlayerController: Duplicate ignored \(model.counter, privacy: .public): \(model.type.debugDescription, privacy: .public) - \(model.subType.debugDescription, privacy: .public), \(model.data.type.token, privacy: .public)")
            return
        }
        await processMessages()
    }

    /// Establishes authority from the first complete master broadcast and then
    /// pins every remote envelope to that session. A locally remapped proxy
    /// presentation is already authenticated by the proxy host controller.
    private func acceptsSessionMessage(
        _ model: GameNetworkModel,
        origin: GameMessageOrigin
    ) async -> Bool {
        let config = root.gameModel.gameConfig
        let acceptsLogicalAuthority: Bool

        if origin == .local {
            acceptsLogicalAuthority = model.masterId == config.master.id
        } else if config.master.type == .master {
            guard model.masterId == config.master.id else { return false }
            if model.sender.isMaster {
                acceptsLogicalAuthority = model.sender.id == config.master.id
            } else {
                acceptsLogicalAuthority = model.sender.id != config.master.id &&
                    model.masterState == nil
            }
        } else {
            // Before discovery, only a self-consistent full master broadcast may
            // establish the authoritative master UUID. Player-to-player traffic
            // cannot race that first message and nominate a different session.
            acceptsLogicalAuthority = model.sender.isMaster &&
                model.sender.id == model.masterId &&
                model.masterState != nil
        }

        guard acceptsLogicalAuthority else { return false }
        guard model.sender.isMaster,
              case let .sharePlay(participantId) = origin
        else { return true }

        // Messenger exposes the physical source participant. Pin that source
        // as well as the logical master UUID so another peer cannot copy the
        // public master identity into a forged envelope. Journal callbacks do
        // not expose a publisher and therefore remain logically authenticated.
        switch gameModel.acceptSharePlayMasterParticipant(
            id: participantId,
            isCompleteMasterBroadcast: model.masterState != nil
        ) {
        case .newlyBound, .alreadyBound:
            return true
        case .rebound:
            // The GroupSession can survive while the master's participant ID
            // changes. Re-announce availability and Character exactly as on a
            // fresh session so the rejoined master rebuilds its reports.
            await ready()
            return true
        case .rejected:
            return false
        }
    }

    private func isRemappedProxyPresentation(_ event: GameMessageEvent) -> Bool {
        let model = event.model
        guard event.origin == .local || event.fromProxy else { return false }
        return model.isPlayerFilePresentationEvent
    }

    private func prepareForProcessing(_ event: GameMessageEvent) async -> Bool {
        let model = event.model

        // Targeted messages are only processed by the addressee. Proxy clients
        // are deliberately invisible upstream and every proxy request is remapped
        // to its host ID, so a target belonging to another host can never live
        // behind this device.
        if let targetId = model.targetId, targetId != root.gameModel.gameConfig.id {
            Logger.networking.debug("PlayerController: Message ignored, targeted at \(targetId, privacy: .public)")
            return false
        }

        if !gameModel.asGameMaster {
            let controls = if let authoritativeControls = model.masterState?.controls {
                authoritativeControls
            } else {
                root.gameModel.gameControl.controls
            }
            if let masterState = model.masterState,
               model.sender.isMaster,
               gameModel.shouldApplyMasterState(from: model.masterId, counter: model.counter) {
                // One MainActor hop for the whole broadcast: applying config,
                // controls and roster in separate steps lets concurrent message
                // builders capture a torn state and send it back to the master.
                // A single @MainActor function call preserves that atomicity the
                // same way `MainActor.run` did — two separate `await`-ed calls
                // would each be a scheduling point another queued task could
                // interleave between.
                applyMasterBroadcastAndResetPlayers(
                    masterId: model.masterId,
                    masterName: model.sender.name,
                    supporterTier: model.sender.supporterTier,
                    state: masterState
                )
            }

            let localId = root.gameModel.gameConfig.id
            let type = root.gameModel.gameType
            let photoSharing = root.gameModel.gameControl.features.photoSharing
            let spaceSharing = root.gameModel.gameControl.features.spaceSharing
            let dicePlayers = root.gameModel.gameControl.features.dicePlayers
            guard type == .proxy || type == .observer || controls.isEmpty || controls.contains(where: { $0.id == localId && $0.show == true }) else {
                Logger.networking.debug("PlayerController: Message will be ignored because of controls \(controls, privacy: .public)")
                return false
            }
            // SharePlay physically broadcasts player-to-master repair requests.
            // Reject them before any module handler; only genuine player group
            // events may use the peer-to-peer presentation path.
            if !model.sender.isMaster, model.effectiveAudience == .master {
                Logger.networking.debug("PlayerController: Master-only player message ignored")
                return false
            }
            let acceptsPlayerPhotoReveal = model.isPlayerFilePresentationEvent &&
                model.data.type == .photo &&
                photoSharing
            let acceptsPlayerPdfReveal = model.isPlayerFilePresentationEvent &&
                model.data.type == .pdf
            let acceptsPlayerSpaceReveal = model.isPlayerFilePresentationEvent &&
                model.data.type == .space &&
                spaceSharing
            let acceptsPlayerDice = model.isPlayerDiceGroupEvent &&
                dicePlayers &&
                model.effectiveAudience == .group
            let acceptsPlayerMapPin = model.sender.role == .player &&
                model.type == .update &&
                model.subType == .mapPin &&
                model.data.type == .map &&
                model.effectiveAudience == .group
            let acceptsPlayerSpaceTransform = model.sender.role == .player &&
                model.type == .update &&
                model.subType == .spaceTransform &&
                model.data.type == .space &&
                spaceSharing &&
                model.effectiveAudience == .group
            guard root.gameModel.gameType == .proxy || model.sender.isMaster || acceptsPlayerDice || acceptsPlayerPhotoReveal || acceptsPlayerPdfReveal || acceptsPlayerSpaceReveal || acceptsPlayerMapPin || acceptsPlayerSpaceTransform else {
                Logger.networking.debug("PlayerController: Message will be ignored because it is send from Player \(model.senderName, privacy: .public)")
                return false
            }
        }

        // Value messages synchronize the joining player's Character and are
        // not part of the presentation ordering state machine.
        if model.data.type != .value,
           (model.isPresentationIntent || model.isMapPresentationRepair) {
            let presentationVersion: Int
            let allowsUnversionedMapState: Bool
            if model.data.type == .map,
               model.type == .update,
               model.subType == .mapState {
                // Live state belongs to the currently intended Map asset. New
                // peers include the asset fingerprint; legacy peers are allowed
                // to repair the same item with an unversioned state only.
                presentationVersion = model.data.assetVersion ?? 0
                allowsUnversionedMapState = model.data.assetVersion == nil
            } else if model.data.type == .map {
                // The legacy MapModel.version covers scales only. The background
                // asset fingerprint is the presentation generation that must
                // reject a delayed Journal attachment for an older background.
                presentationVersion = model.data.effectiveAssetVersion
                allowsUnversionedMapState = false
            } else {
                presentationVersion = model.data.version
                allowsUnversionedMapState = false
            }
            let shouldProcess = gameModel.shouldProcessPresentation(
                from: model.masterId,
                senderID: model.sender.id,
                module: model.data.type,
                itemId: model.data.id,
                version: presentationVersion,
                counter: model.counter,
                timestamp: model.timestamp,
                isRepair: model.targetId != nil || model.isMapPresentationRepair,
                allowsUnversionedStateRepair: model.isTargetedMapStatePresentationRepair || allowsUnversionedMapState
            )
            guard shouldProcess else {
                Logger.networking.debug("PlayerController: Stale presentation ignored \(model.counter, privacy: .public), \(model.data.type.token, privacy: .public) id: \(model.data.id, privacy: .public)")
                return false
            }
        }

        if !event.fromProxy, event.origin != .local, !model.isAcknowledgement {
            if model.data.type != .value {
                // Proxy clients mirror this player: an answer addressed to this
                // device must be processed by them too, so clear the target before
                // forwarding. Messages targeted at other hosts were already
                // rejected above and never reach this point. Character bootstrap bypasses
                // this path and is sent directly by the proxy master controller.
                var forwarded = model
                if forwarded.targetId == root.gameModel.gameConfig.id {
                    forwarded.targetId = nil
                }
                await root.networkProxyStore.sendPlayer(data: forwarded)
            }
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
                    usesSharePlayPlaybackCoordination: event.origin.usesSharePlayFileTransport,
                    locallyMirroredProxyPresentation: isRemappedProxyPresentation(event)
                )
                try Task.checkCancellation()
                if let response, event.origin != .local {
                    await sendUpstream(model: response)
                    if response.subType == .ok {
                        gameModel.increaseMessageCounter()
                    }
                } else {
                    gameModel.increaseMessageCounter()
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
                if event.origin != .local {
                    let failure = await response(for: event.model, isSuccess: false, requestData: false)
                    await sendUpstream(model: failure)
                }
                await messagePipeline.processed(success: false)
            }
        }
    }
}
