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
final class MasterControllerModel {
    private struct SpaceTransformSequenceKey: Hashable, Sendable {
        let playerId: UUID
        let itemId: UUID
        let version: Int
    }

    private struct PlayerJournalAdmissionKey: Hashable, Sendable {
        let senderId: UUID
        let messageId: UUID
    }

    private struct PlayerJournalAdmission: Equatable, Sendable {
        let envelopeVersion: Int
        let replyToMessageId: UUID?
        let masterId: UUID
        let sender: GameSenderModel
        let masterState: GameMasterStateModel?
        let counter: Int
        let proxyCounter: Int
        let type: RPGMessageType
        let subType: RPGMessageActionType
        let audience: GameMessageAudience
        let purpose: GameMessagePurpose
        let targetId: UUID?
        let itemId: UUID
        let module: NetworkModules
        let version: Int
        let assetVersion: Int?
        let contentVersion: Int?
        let timestamp: TimeInterval
        let journalPayloadDigest: Data?

        init(_ model: GameNetworkModel) {
            envelopeVersion = model.version
            replyToMessageId = model.replyToMessageID
            masterId = model.masterId
            sender = model.sender
            masterState = model.masterState
            counter = model.counter
            proxyCounter = model.proxyCounter
            type = model.type
            subType = model.subType
            audience = model.audience
            purpose = model.purpose
            targetId = model.targetId
            itemId = model.data.id
            module = model.data.type
            version = model.data.version
            assetVersion = model.data.assetVersion
            contentVersion = model.data.contentVersion
            timestamp = model.timestamp
            if let payload = model.data.data {
                journalPayloadDigest = GameNetworkModel.journalDigest(for: payload)
            } else {
                journalPayloadDigest = model.journalPayloadDigest
            }
        }
    }

    private struct PeerAvailabilitySource: Equatable, Sendable {
        let wireId: UUID?
        let presenterId: UUID
        let masterId: UUID
        let counter: Int
        let proxyCounter: Int
        let type: RPGMessageType
        let itemId: UUID
        let module: NetworkModules
        let version: Int
        let assetVersion: Int?
        let contentVersion: Int?
        var pendingRecipients: Set<UUID>

        init(_ model: GameNetworkModel, recipients: Set<UUID>) {
            wireId = model.messageID
            presenterId = model.sender.id
            masterId = model.masterId
            counter = model.counter
            proxyCounter = model.proxyCounter
            type = model.type
            itemId = model.data.id
            module = model.data.type
            version = model.data.version
            assetVersion = model.data.assetVersion
            contentVersion = model.data.contentVersion
            pendingRecipients = recipients
        }

        func matches(_ receipt: GameNetworkModel) -> Bool {
            let hasMatchingIdentity = if let wireId {
                receipt.replyToMessageID == wireId
            } else {
                // Shipped V1 envelopes have no message identity. Their echoed
                // counter plus the complete asset fingerprint is the strongest
                // correlation available to a mixed-version session.
                receipt.replyToMessageID == nil && receipt.counter == counter
            }
            return hasMatchingIdentity &&
                receipt.masterId == masterId &&
                receipt.counter == counter &&
                receipt.proxyCounter == proxyCounter &&
                receipt.type == type &&
                receipt.data.id == itemId &&
                receipt.data.type == module &&
                receipt.data.version == version &&
                receipt.data.assetVersion == assetVersion &&
                receipt.data.contentVersion == contentVersion
        }

        func identifiesSamePresentation(as other: Self) -> Bool {
            wireId == other.wireId &&
                presenterId == other.presenterId &&
                masterId == other.masterId &&
                counter == other.counter &&
                proxyCounter == other.proxyCounter &&
                type == other.type &&
                itemId == other.itemId &&
                module == other.module &&
                version == other.version &&
                assetVersion == other.assetVersion &&
                contentVersion == other.contentVersion
        }
    }

    var messageCounter: Int = 1
    var connectIDPlayers: [ConnectionController.ID: UUID] = [:]
    private var connectionRoles: [ConnectionController.ID: GameType] = [:]
    private var retiredConnectionIDs: Set<ConnectionController.ID> = []
    let deliverySessionID = UUID()
    private var deliveryMessagesByWireID: [UUID: GameDeliveryMessageID] = [:]
    private var deliveryMessagesByWireIDOrder: [UUID] = []
    private static let maximumDeliveryMessagesByWireID = 256
    var asProxy = false
    var pendingAudioPlays: [UUID: NetworkCodableDataType] = [:]
    var audioTransferPlayers: [UUID: Set<UUID>] = [:]
    private var lastAudioListCounters: [UUID: Int] = [:]
    private var lastPhotoListCounters: [UUID: Int] = [:]
    private var lastPdfListCounters: [UUID: Int] = [:]
    private var lastSpaceListCounters: [UUID: Int] = [:]
    private var lastSpaceTransformCounters: [SpaceTransformSequenceKey: Int] = [:]
    private var playerJournalAdmissions: [PlayerJournalAdmissionKey: PlayerJournalAdmission] = [:]
    private var playerJournalAdmissionOrder: [PlayerJournalAdmissionKey] = []
    private static let maximumPlayerJournalAdmissions = 256
    private var peerAvailabilitySources: [PeerAvailabilitySource] = []
    private static let maximumPeerAvailabilitySources = 256
    /// Latest file-backed item versions whose full package already went out in
    /// the current game. A changed version must be broadcast in full again;
    /// otherwise a new map is reduced to a reference and unnecessarily falls
    /// back to a requester-only SharePlay chunk transfer.
    var sentGameItems: [NetworkModules: [UUID: Int]] = [:]

    /// Which Character id each sender is authorized to act on — established
    /// once at that sender's join handshake and enforced on every later
    /// `.value` message. `sender.characterId` is otherwise self-declared,
    /// untrusted network input every peer can already read off the wire
    /// (encoded in `.mapState`). See CODE_AUDIT_Game §6.1.
    private var characterOwnership: [UUID: UUID] = [:]

    /// Binds `senderId` to `characterId` if this is their first claim, or
    /// confirms it matches their existing binding. Rejects the claim if a
    /// *different* sender already owns this Character. Call only from the
    /// `.store` join handshake — see `isCharacterOwnershipAuthorized` for the
    /// read-only check every later message must use instead, so a message
    /// arriving before the real owner's join can't squat the binding.
    @discardableResult
    func bindCharacterOwnership(senderId: UUID, characterId: UUID) -> Bool {
        if characterOwnership.contains(where: { $0.key != senderId && $0.value == characterId }) {
            return false
        }
        if let bound = characterOwnership[senderId] {
            return bound == characterId
        }
        characterOwnership[senderId] = characterId
        return true
    }

    /// Read-only enforcement for every `.value` message after the join
    /// handshake — never creates a binding itself.
    func isCharacterOwnershipAuthorized(senderId: UUID, characterId: UUID) -> Bool {
        characterOwnership[senderId] == characterId
    }

    func resetCharacterOwnership() {
        characterOwnership.removeAll()
    }

    func hasSentGameItem(type: NetworkModules, id: UUID, version: Int) -> Bool {
        sentGameItems[type]?[id] == version
    }

    func markSentGameItem(type: NetworkModules, id: UUID, version: Int) {
        sentGameItems[type, default: [:]][id] = version
    }

    /// Rolls back a reservation `markSentGameItem` made before an export that
    /// then failed, but only if nothing else has since marked a *newer*
    /// version sent for the same item — an out-of-order rollback must not
    /// erase a valid, more recent mark. See CODE_AUDIT_Game §3.9.
    func unmarkSentGameItem(type: NetworkModules, id: UUID, version: Int) {
        guard sentGameItems[type]?[id] == version else { return }
        sentGameItems[type]?[id] = nil
    }
    
    /// Reserves the next counter atomically. Reading and incrementing in separate
    /// calls lets concurrent sends stamp the same counter, which the receivers'
    /// deduplication then treats as one message.
    func nextMessageCounter() -> Int {
        defer { messageCounter += 1 }
        return messageCounter
    }

    @discardableResult
    func add(
        connectionId: ConnectionController.ID,
        playerId: UUID,
        role: GameType = .player
    ) -> Bool {
        guard !retiredConnectionIDs.contains(connectionId) else { return false }
        if let existingPlayerID = connectIDPlayers[connectionId] {
            return existingPlayerID == playerId && connectionRoles[connectionId] == role
        }
        // A live physical source owns its public UUID until that source is
        // explicitly retired. A second connection cannot seize the identity.
        guard !connectIDPlayers.contains(where: { $0.key != connectionId && $0.value == playerId }) else {
            return false
        }
        connectIDPlayers[connectionId] = playerId
        connectionRoles[connectionId] = role
        return true
    }

    /// Binds one physical LAN/SharePlay/proxy connection to one logical sender.
    /// A connection may reconnect under a new physical ID, but an established
    /// physical origin cannot change identities mid-stream.
    func accepts(connectionId: ConnectionController.ID, sender: GameSenderModel) -> Bool {
        guard !retiredConnectionIDs.contains(connectionId) else { return false }
        if let existingPlayerId = connectIDPlayers[connectionId] {
            return existingPlayerId == sender.id && connectionRoles[connectionId] == sender.role
        }
        return add(
            connectionId: connectionId,
            playerId: sender.id,
            role: sender.role
        )
    }

    /// Compatibility helper for focused model tests and older direct callers.
    func accepts(connectionId: ConnectionController.ID, playerId: UUID) -> Bool {
        accepts(
            connectionId: connectionId,
            sender: GameSenderModel(id: playerId, role: .player, name: "", characterId: nil)
        )
    }

    /// Lifts a prior retirement for exactly the physical ID GroupSession just
    /// reported as newly active. SharePlay can reissue a departed
    /// participant's UUID to the same device on rejoin (unlike Bonjour/proxy
    /// connection IDs, which are always freshly minted); without this, a
    /// crash-and-relaunch permanently locks that player out because
    /// `retiredConnectionIDs` never otherwise forgets an ID. Only an
    /// OS-confirmed `activeParticipants` addition may call this — never a
    /// claim carried inside message content.
    func reinstateConnection(_ connectionId: ConnectionController.ID) {
        retiredConnectionIDs.remove(connectionId)
    }

    func remove(connectionId: ConnectionController.ID) -> UUID? {
        retiredConnectionIDs.insert(connectionId)
        connectionRoles[connectionId] = nil
        guard let playerId = connectIDPlayers.removeValue(forKey: connectionId) else { return nil }
        lastAudioListCounters[playerId] = nil
        lastPhotoListCounters[playerId] = nil
        lastPdfListCounters[playerId] = nil
        lastSpaceListCounters[playerId] = nil
        lastSpaceTransformCounters = lastSpaceTransformCounters.filter { $0.key.playerId != playerId }
        removePlayerJournalAdmissions(for: playerId)
        for index in peerAvailabilitySources.indices {
            peerAvailabilitySources[index].pendingRecipients.remove(playerId)
        }
        peerAvailabilitySources.removeAll { $0.pendingRecipients.isEmpty }
        return playerId
    }

    @discardableResult
    func admitPlayerJournalMetadata(_ model: GameNetworkModel) -> Bool {
        guard model.isPlayerJournalAdmissionMetadata,
              let messageId = model.messageID
        else { return false }

        let key = PlayerJournalAdmissionKey(
            senderId: model.sender.id,
            messageId: messageId
        )
        let admission = PlayerJournalAdmission(model)
        if let existing = playerJournalAdmissions[key] {
            // Never let a copied sender/message ID replace the first
            // physically attributed Journal fingerprint.
            return existing == admission
        }
        playerJournalAdmissionOrder.append(key)
        playerJournalAdmissions[key] = admission
        while playerJournalAdmissionOrder.count > Self.maximumPlayerJournalAdmissions {
            playerJournalAdmissions[playerJournalAdmissionOrder.removeFirst()] = nil
        }
        return true
    }

    func acceptsPlayerJournal(_ model: GameNetworkModel) -> Bool {
        guard model.isPlayerFilePresentationEvent,
              let messageId = model.messageID
        else { return false }

        let key = PlayerJournalAdmissionKey(
            senderId: model.sender.id,
            messageId: messageId
        )
        return playerJournalAdmissions[key] == PlayerJournalAdmission(model)
    }

    func resetPlayerJournalAdmissions() {
        playerJournalAdmissions.removeAll()
        playerJournalAdmissionOrder.removeAll()
    }

    private func removePlayerJournalAdmissions(for playerId: UUID) {
        playerJournalAdmissions = playerJournalAdmissions.filter {
            $0.key.senderId != playerId
        }
        playerJournalAdmissionOrder.removeAll { $0.senderId == playerId }
    }

    func trackDelivery(wireID: UUID, counter: Int) -> GameDeliveryMessageID {
        let messageID = GameDeliveryMessageID(
            sessionID: deliverySessionID,
            counter: counter
        )
        deliveryMessagesByWireID[wireID] = messageID
        // Bounded FIFO, mirroring `playerJournalAdmissions`/`peerAvailabilitySources`: this
        // gets a new entry for nearly every outgoing master message, so over a long-running
        // session it would otherwise grow indefinitely. See CODE_AUDIT §5.20.
        deliveryMessagesByWireIDOrder.append(wireID)
        while deliveryMessagesByWireIDOrder.count > Self.maximumDeliveryMessagesByWireID {
            deliveryMessagesByWireID[deliveryMessagesByWireIDOrder.removeFirst()] = nil
        }
        return messageID
    }

    func deliveryMessageID(replyingTo wireID: UUID) -> GameDeliveryMessageID? {
        deliveryMessagesByWireID[wireID]
    }

    func resetDeliveryMessages() {
        deliveryMessagesByWireID.removeAll()
        deliveryMessagesByWireIDOrder.removeAll()
    }

    func trackPeerAvailabilitySource(
        _ model: GameNetworkModel,
        recipients: Set<UUID>
    ) {
        // The presenting player was already required to report the canonical
        // asset before its event was accepted. Only the other recipients need
        // to prove that this peer-origin transfer reached them.
        let pendingRecipients = recipients.subtracting([model.sender.id])
        guard model.isPlayerFilePresentationEvent, !pendingRecipients.isEmpty else {
            return
        }
        let source = PeerAvailabilitySource(model, recipients: pendingRecipients)
        guard !peerAvailabilitySources.contains(where: {
            $0.identifiesSamePresentation(as: source)
        }) else { return }
        peerAvailabilitySources.append(source)
        while peerAvailabilitySources.count > Self.maximumPeerAvailabilitySources {
            peerAvailabilitySources.removeFirst()
        }
    }

    func acceptsPeerAvailabilityReceipt(_ model: GameNetworkModel) -> Bool {
        guard model.subType == .ok,
              let index = peerAvailabilitySources.firstIndex(where: {
                  $0.pendingRecipients.contains(model.sender.id) &&
                      $0.matches(model)
              })
        else { return false }

        peerAvailabilitySources[index].pendingRecipients.remove(model.sender.id)
        if peerAvailabilitySources[index].pendingRecipients.isEmpty {
            peerAvailabilitySources.remove(at: index)
        }
        return true
    }

    /// Test affordance. See CODE_AUDIT_Game §9.22.
    var trackedPeerAvailabilitySourceCount: Int {
        peerAvailabilitySources.count
    }

    func resetPeerAvailabilitySources() {
        peerAvailabilitySources.removeAll()
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

@MainActor
final class MasterController {
    private struct MapRecoveryBundle: Sendable {
        let full: NetworkCodableDataType
        let content: NetworkCodableDataType
        let state: NetworkCodableDataType
    }

    private enum MapRecoveryError: Error {
        case generationChanged
    }

    /// The outermost of three nested retry levels — see
    /// `MapRPG.GameController.maximumPackageExportAttempts`'s doc comment for
    /// the full compounding chain. See CODE_AUDIT_Game §9.13.
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

    /// Chains every `resetPlayers()` call onto the previous one so only a
    /// single broadcast sequence is ever in flight, regardless of which of
    /// `resetPlayers()`'s three independent call sites triggered it — the
    /// `messagePipeline`-drained network path, `lostPlayer(for:)` (called
    /// directly on connection loss, bypassing `messagePipeline`), and
    /// `GameRootModel.sharingControlActions`'s own, separately-serialized
    /// `scheduleNetworkAction` chain. Without this, `resetPlayers()`'s
    /// several internal `await`s let two independently triggered calls
    /// interleave and each broadcast its own stale roster/map snapshot. See
    /// CODE_AUDIT_10 §3.1.
    private var resetPlayersTask: Task<Void, Never>?

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
    func start() async {
        Logger.networking.debug("MasterController: Start")
        gameModel.resetPlayerJournalAdmissions()
        gameModel.resetPeerAvailabilitySources()
        root.logGameController.beginDeliverySession(gameModel.deliverySessionID)
        await root.networkStore.startMasterGame(
            game: root.gameModel.gameConfig,
            titleImage: root.adventureRoot.titleImage(for: root.gameModel.gameConfig.master.adventureId),
            passcode: root.gameJoinCodeModel.masterCode
        )
    }
    
    func stop() async {
        Logger.networking.debug("MasterController: Stop")
        await messagePipeline.cancelAll()
        resetPlayersTask?.cancel()
        resetPlayersTask = nil
        gameModel.pendingAudioPlays.removeAll()
        gameModel.audioTransferPlayers.removeAll()
        gameModel.sentGameItems.removeAll()
        gameModel.resetCharacterOwnership()
        gameModel.resetAudioListSequence()
        gameModel.resetPhotoListSequence()
        gameModel.resetPdfListSequence()
        gameModel.resetSpaceListSequence()
        gameModel.resetSpaceTransformSequence()
        gameModel.resetDeliveryMessages()
        gameModel.resetPlayerJournalAdmissions()
        gameModel.resetPeerAvailabilitySources()
        await root.networkStore.stopGame()
        await root.networkProxyStore.stopGame()
        await root.adventureRoot.adventureGameControllable.resetGame()
        root.gameModel.gameRoster.players = []
        root.gameModel.gameControl.controls = []
    }
    
    /// Serializing entry point — see `resetPlayersTask`'s doc comment. Every
    /// call site awaits this, so each caller still only returns once its own
    /// broadcast sequence (and any it was queued behind) has fully run.
    func resetPlayers() async {
        let previous = resetPlayersTask
        let task = Task { @MainActor [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled else { return }
            await self.performResetPlayers()
        }
        resetPlayersTask = task
        await task.value
    }

    private func performResetPlayers() async {
        let (gameConfig, gameRoster, gameControl) = (root.gameModel.gameConfig, root.gameModel.gameRoster, root.gameModel.gameControl)

        let previousAudioPlayers = Set(root.audioRoot.gameControllable.gameModel.currentPlayers)
        var players = gameControl.controls.compactMap { $0.show ? $0.id : nil }.sorted()
        if asProxy {
            players.append(gameConfig.master.id)
            players.sort()
        }
        // See CODE_AUDIT_Game §9.18 — Map and Dice have their own reset logic below.
        for controllable in root.fileBackedGameModules {
            controllable.gameModel.setCurrent(players: players)
        }

        var playerNames = gameRoster.players.filter { $0.type != .observer }.map { $0.name }.sorted()
        if asProxy {
            playerNames.append(gameConfig.master.name)
            playerNames.sort()
        }
        root.diceRoot.diceGameControllable.resetPlayerDice(to: playerNames)
        if !asProxy {
            root.mapRoot.mapGameControllable.resetPlayerPins(for: gameRoster.players.filter { $0.type != .observer })
            #if !os(tvOS)
            root.gameModel.gameTableModel?.syncPawnsWithMapPins()
            #endif
            // Push the changed player pins to everyone right away — otherwise
            // a joining player's pin only appears on the next unrelated map
            // state update.
            if let mapId = root.mapRoot.gameControllable.gameModel.currentItemId {
                // Messenger messages have no history. Replay the latest
                // photo-free structural snapshot when the roster changes so a
                // SharePlay participant joining after the Journal publication
                // receives edits made since that base attachment.
                await send(
                    type: .update,
                    subtype: .generic,
                    updated: root.mapRoot.mapGameControllable.networkMapContentUpdate(for: mapId)
                )
                await send(type: .update, subtype: .mapState, updated: root.mapRoot.mapGameControllable.networkMapUpdate(for: mapId))
                if root.mapRoot.mapGameControllable.battleRoundModel.isRunning,
                   let battleUpdate = root.mapRoot.mapGameControllable.networkBattleRoundUpdate(
                       for: mapId
                   ) {
                    await send(type: .update, subtype: .battleRound, updated: battleUpdate)
                }
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
            let masterId = root.gameModel.gameConfig.id
            root.spaceRoot.spaceGameControllable.setMasterVersion(
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
        if Self.sendsFullPayloadOnFirstShow(resolvedIdType.type), !gameModel.hasSentGameItem(type: resolvedIdType.type, id: resolvedIdType.id, version: resolvedIdType.effectiveAssetVersion) {
            // Reserved before the export `await` (not after it succeeds) so the
            // receive path can't independently decide to publish the same
            // item/version during the suspension and double the broadcast.
            // Rolled back below if the export fails. See CODE_AUDIT_Game §3.9.
            gameModel.markSentGameItem(type: resolvedIdType.type, id: resolvedIdType.id, version: resolvedIdType.effectiveAssetVersion)
            if let fullData = try? await createGameData(for: resolvedIdType) {
                await send(type: .reveal, subtype: .show, updated: fullData)
                if fullData.type == .map,
                   let battleUpdate = root.mapRoot.mapGameControllable.networkBattleRoundUpdate(
                       for: fullData.id
                   ),
                   root.mapRoot.mapGameControllable.battleRoundModel.isRunning {
                    await send(type: .update, subtype: .battleRound, updated: battleUpdate)
                }
                return
            }
            gameModel.unmarkSentGameItem(type: resolvedIdType.type, id: resolvedIdType.id, version: resolvedIdType.effectiveAssetVersion)
            Logger.networking.error("MasterController: Cannot create package for \(resolvedIdType.type.token, privacy: .public) \(resolvedIdType.id, privacy: .public) — sending reference instead")
        }
        await send(type: .reveal, subtype: .show, updated: resolvedIdType)
        if resolvedIdType.type == .map,
           let battleUpdate = root.mapRoot.mapGameControllable.networkBattleRoundUpdate(
               for: resolvedIdType.id
           ),
           root.mapRoot.mapGameControllable.battleRoundModel.isRunning {
            await send(type: .update, subtype: .battleRound, updated: battleUpdate)
        }
    }

    static func sendsFullPayloadOnFirstShow(_ type: NetworkModules) -> Bool {
        switch type {
        case .map, .photo, .pdf, .space, .weather:
            true
        default:
            false
        }
    }

    /// `createGameData`/`createMapGameData`/`createWeatherGameData` are
    /// `nonisolated async` protocol requirements — under this project's
    /// approachable-concurrency setting they otherwise run on the *caller's*
    /// actor (see CODE_AUDIT_Game §3.1's mechanism), which for every call
    /// site of this dispatcher is the main actor. `Task.detached` here gives
    /// the export an explicit off-main starting point, matching the pattern
    /// `ImportControllable.importUrl` already uses; the implementation still
    /// hops back to the main actor itself for whatever pieces genuinely need
    /// it. Each controllable is fetched on the main actor first and handed
    /// into the detached task by value, rather than capturing `root` itself
    /// (a plain, non-`Sendable` class). See CODE_AUDIT_Game §3.5.
    private func createGameData(for idType: NetworkCodableDataType) async throws -> NetworkCodableDataType? {
        switch idType.type {
        case .map:
            let controllable = root.mapRoot.mapGameControllable
            return try await detachedGameData {
                try await controllable.createMapGameData(for: idType.id)
            }
        case .photo:
            let controllable = root.photoRoot.gameControllable
            return try await detachedGameData {
                try await controllable.createGameData(for: idType.id)
            }
        case .pdf:
            let controllable = root.pdfRoot.gameControllable
            return try await detachedGameData {
                try await controllable.createGameData(for: idType.id)
            }
        case .space:
            let controllable = root.spaceRoot.gameControllable
            return try await detachedGameData {
                try await controllable.createGameData(for: idType.id)
            }
        case .weather:
            let controllable = root.weatherRoot.weatherGameControllable
            return try await detachedGameData {
                try await controllable.createWeatherGameData(for: idType.id)
            }
        default:
            return nil
        }
    }

    /// Runs `operation` on a detached, off-main task and propagates
    /// cancellation of the *caller's* task into it, matching the pattern
    /// used everywhere else in the codebase a detached task wraps an
    /// awaited result (e.g. `FoundrySystemPackageReader.read`,
    /// `FoundryVTTImportReader`, `ImportControllable.importUrl`). Without
    /// this, cancelling a reveal/repair/recovery left the detached export
    /// running to completion regardless. See CODE_AUDIT_9 §3.1.
    private func detachedGameData<Value: Sendable>(
        priority: TaskPriority = .userInitiated,
        _ operation: @Sendable @escaping () async throws -> Value
    ) async throws -> Value {
        let task = Task.detached(priority: priority) {
            try await operation()
        }
        return try await withTaskCancellationHandler {
            let value = try await task.value
            try Task.checkCancellation()
            return value
        } onCancel: {
            task.cancel()
        }
    }
    
    func game(message: NetworkCodableDataType, actionType: RPGMessageActionType, playerId: UUID? = nil) async {
        // Weather is immutable during a game. It is presented and repaired via
        // reveal messages only; live update messages are not supported yet.
        guard message.type != .table, message.type != .weather else { return }
        // Character/Value updates have no general in-game protocol — the
        // player join handshake has its own exchange elsewhere, and the only
        // Value push a master can trigger here is `.addItem` (a Table-
        // generated outcome sent to a player as a new Character value).
        guard message.type != .value || actionType == .addItem else { return }
        if message.type == .dice,
           actionType == .generic,
           let diceResult = DiceResultModel.decodeData(of: message.data) {
            root.battleRoundController.recordDiceResult(
                diceResult,
                senderId: root.gameModel.gameConfig.id,
                isMaster: true
            )
        }
        if message.type == .audio, actionType == .playAudio {
            await requestAudioPlay(message)
            return
        }
        if message.type == .space, actionType == .spaceTransform {
            guard root.spaceRoot.spaceGameControllable.isValidSpaceTransform(message),
                  root.spaceRoot.gameControllable.gameModel.currentItemId == message.id
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

    func send(
        type: RPGMessageType,
        subtype: RPGMessageActionType,
        updated: NetworkCodableDataType,
        replyToMessageID: UUID? = nil,
        timestamp: TimeInterval? = nil,
        appliesLocalSpaceTransform: Bool = true,
        connectionId: ConnectionController.ID? = nil,
        origin: GameMessageOrigin? = nil,
        playerId: UUID? = nil,
        authoritativeMaster: Bool? = nil
    ) async {
        // Tables are immutable during a game. Their complete state is exchanged
        // only through reveal/store requests; accepting an update would bypass
        // the versioned canonical-package handshake.
        guard type != .update || updated.type != .table else { return }

        let outgoingTimestamp: TimeInterval
        if let timestamp {
            outgoingTimestamp = timestamp
        } else if appliesLocalSpaceTransform,
                  type == .update,
                  subtype == .spaceTransform,
                  updated.type == .space {
            guard let causalTimestamp = root.spaceRoot.spaceGameControllable
                .causalSpaceTransformTimestamp(
                    itemId: updated.id,
                    version: updated.effectiveAssetVersion
                )
            else { return }
            outgoingTimestamp = causalTimestamp
        } else {
            outgoingTimestamp = Date.now.timeIntervalSince1970
        }

        let counter = gameModel.nextMessageCounter()
        Logger.networking.debug("MasterController: Send \(counter, privacy: .public): \(type.debugDescription, privacy: .public) - \(subtype.debugDescription, privacy: .public) for \(updated.type.token, privacy: .public) -> \(updated.id, privacy: .public)")

        // Built from local state in one MainActor hop; a playerId becomes the
        // message target so only the addressee processes it.
        let networtData = root.gameModel.outgoingMessage(
            replyToMessageID: replyToMessageID,
            timestamp: outgoingTimestamp,
            counter: counter,
            type: type,
            subType: subtype,
            asMaster: authoritativeMaster ?? !asProxy,
            targetId: playerId,
            data: updated
        )

        if !asProxy,
           appliesLocalSpaceTransform,
           networtData.sender.isMaster,
           type == .update,
           subtype == .spaceTransform {
            guard root.spaceRoot.spaceGameControllable.applySpaceTransform(
                data: networtData.data,
                counter: networtData.counter,
                timestamp: networtData.timestamp
            ) else { return }
        }

        if let wireID = networtData.messageID {
            let deliveryID = gameModel.trackDelivery(
                wireID: wireID,
                counter: counter
            )
            root.logGameController.addMessage(
                messageID: deliveryID,
                type: type,
                subType: subtype,
                module: updated.type,
                itemId: updated.id,
                targetID: networtData.targetId
            )
        } else {
            root.logGameController.addMessage(
                counter: counter,
                type: type,
                subType: subtype,
                module: updated.type,
                itemId: updated.id
            )
        }
        let deliveryOrigin = origin ?? (asProxy ? .proxy(connectionId) : .direct(connectionId))
        await root.statisticsModel.record(
            networtData,
            direction: .outgoing,
            origin: deliveryOrigin
        )

        if asProxy {
            if let targetConnectionId = origin?.connectionId ?? connectionId {
                await root.networkProxyStore.sendPlayer(networtData, to: targetConnectionId)
            } else {
                await root.networkProxyStore.sendPlayer(data: networtData)
            }
        } else if let origin {
            await root.networkStore.sendPlayer(networtData, to: origin)
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
    func accepts(_ model: GameNetworkModel, origin: GameMessageOrigin) async -> Bool {
        let expectedMasterId = root.gameModel.gameConfig.master.id

        // Every message entering the master's receive side came from a remote
        // player transport. A remote endpoint can never acquire authority by
        // changing only its encoded role or by reusing the master's sender ID.
        guard !model.sender.isMaster,
              model.sender.id != expectedMasterId,
              model.masterState == nil
        else {
            Logger.networking.debug("MasterController: Rejected remote master claim from \(model.sender.id, privacy: .public)")
            return false
        }

        guard acceptsTransportRole(model.sender.role, origin: origin) else {
            Logger.networking.debug("MasterController: Rejected \(String(describing: model.sender.role), privacy: .public) sender on incompatible transport")
            return false
        }

        // Players do not know the master's UUID before the first authoritative
        // response. Preserve only the exact master-only bootstrap packets sent
        // at join; every gameplay/peer-visible event must already name this
        // session's master.
        guard model.masterId == expectedMasterId || Self.isPlayerBootstrapEnvelope(model) else {
            Logger.networking.debug("MasterController: Rejected message for another master \(model.masterId, privacy: .public)")
            return false
        }

        guard !model.isPlayerFilePresentationEvent ||
                GameNetworkModel.acceptsEventTimestamp(model.timestamp)
        else {
            Logger.networking.debug("MasterController: Rejected player presentation with invalid timestamp")
            return false
        }

        if model.isJournalAdmissionOnly {
            guard case .sharePlay = origin else {
                Logger.networking.debug("MasterController: Rejected Journal admission on a non-SharePlay transport")
                return false
            }
        }

        if let connectionId = origin.participantConnectionId {
            guard gameModel.accepts(
                connectionId: connectionId,
                sender: model.sender
            ) else { return false }

            // A player Journal attachment has no physical source identity.
            // Admit its exact fingerprint only after the same message arrives
            // through participant-attributed SharePlay Messenger.
            if case .sharePlay = origin,
               model.isPlayerJournalAdmissionMetadata {
                guard gameModel.admitPlayerJournalMetadata(model) else {
                    Logger.networking.debug("MasterController: Rejected conflicting player Journal admission")
                    return false
                }
            }
            return true
        }

        if origin == .file {
            guard gameModel.acceptsPlayerJournal(model) else {
                Logger.networking.debug("MasterController: Rejected uncorrelated Journal sender \(model.sender.id, privacy: .public)")
                return false
            }
        }
        return true
    }

    /// Transport topology is part of sender authority, not merely a routing
    /// detail. Bonjour players and observers connect to the main master;
    /// SharePlay and Journal accept only players; private LAN mirrors connect
    /// only to the host player's proxy master.
    private nonisolated func acceptsTransportRole(
        _ role: GameType,
        origin: GameMessageOrigin
    ) -> Bool {
        switch (asProxy, origin) {
        case (false, .direct(_)):
            role == .player || role == .observer
        case (false, .sharePlay(_)), (false, .file):
            role == .player
        case (true, .proxy(_)):
            role == .proxy
        case (false, .proxy(_)), (false, .local),
             (true, .direct(_)), (true, .sharePlay(_)),
             (true, .file), (true, .local):
            false
        }
    }

    private nonisolated static func isPlayerBootstrapEnvelope(_ model: GameNetworkModel) -> Bool {
        guard model.sender.role == .player ||
                model.sender.role == .observer ||
                model.sender.role == .proxy,
              model.effectiveAudience == .master
        else { return false }

        switch (model.type, model.subType, model.data.type) {
        case (.update, .audioList, .audio),
             (.update, .photoList, .photo),
             (.update, .pdfList, .pdf),
             (.update, .spaceList, .space),
             (.update, .store, .value),
             (.store, .store, .setting):
            return true
        default:
            return false
        }
    }

    func ready(for origin: GameMessageOrigin) async {
        Logger.networking.debug("MasterController: Participant ready")
        if let participantId = origin.sharePlayParticipantId {
            // GroupSession can reissue this participant's UUID to the same
            // device after a crash/relaunch rejoin. Trust only this
            // OS-confirmed join to clear an earlier retirement so the
            // reconnected player's messages bind again instead of being
            // rejected forever.
            gameModel.reinstateConnection(participantId)
        }
        await replayCurrentPresentation(to: origin)
    }
    
    func lostPlayer(for connectionId: ConnectionController.ID) async {
        Logger.networking.debug("MasterController: Lost Player for \(connectionId, privacy: .public)")
        guard let playerId = gameModel.remove(connectionId: connectionId) else { return }
        root.audioRoot.gameControllable.gameModel.removePlayerReport(for: playerId)
        root.photoRoot.photoGameControllable.removePhotoReports(for: playerId)
        root.pdfRoot.pdfGameControllable.removePdfReports(for: playerId)
        root.spaceRoot.spaceGameControllable.removeSpaceReports(for: playerId)
        root.tableRoot.gameControllable.gameModel.removePlayerReport(for: playerId)
        root.weatherRoot.gameControllable.gameModel.removePlayerReport(for: playerId)
        if root.gameModel.remove(playerId: playerId) {
            await root.statisticsModel.participantLeft(id: playerId)
            await resetPlayers()
        }
    }
    
    func received(_ model: GameNetworkModel, connectionId: ConnectionController.ID?) async {
        await receivedProcess(model, connectionId: connectionId)
    }

    func received(_ model: GameNetworkModel, origin: GameMessageOrigin) async {
        await receivedProcess(model, origin: origin)
    }
    
    func receivedProcess(_ model: GameNetworkModel, connectionId: ConnectionController.ID?) async {
        await receivedProcess(model, origin: .direct(connectionId))
    }

    private func receivedProcess(_ model: GameNetworkModel, origin: GameMessageOrigin) async {
        Logger.networking.debug("MasterController: Received \(model.counter, privacy: .public): \(model.type.debugDescription, privacy: .public) - \(model.subType.debugDescription, privacy: .public), \(model.data.type.token, privacy: .public) id: \(model.data.id, privacy: .public)")

        guard await accepts(model, origin: origin) else { return }

        let event = GameMessageEvent(model: model, origin: origin)
        guard await messagePipeline.enqueue(event) else {
            Logger.networking.debug("MasterController: Duplicate ignored \(model.counter, privacy: .public): \(model.type.debugDescription, privacy: .public) - \(model.subType.debugDescription, privacy: .public), \(model.data.type.token, privacy: .public)")
            return
        }
        await processMessages()
    }

    private func processMessages() async {
        while let event = await messagePipeline.next() {
            // Matches PlayerController.processMessages' policy: stop
            // draining on cancellation rather than continuing to process
            // (or silently drop) the remaining backlog — the pipeline
            // retains any still-queued events for the next real trigger to
            // resume, instead of the two controllers disagreeing about what
            // cancellation means. See CODE_AUDIT_Game §3.8.
            guard !Task.isCancelled else {
                await messagePipeline.processed(success: false)
                return
            }
            let success = await process(event)
            await messagePipeline.processed(success: success)
        }
    }

    private func process(_ event: GameMessageEvent) async -> Bool {
        let receivedModel = event.model

        // Before the roster add: a proxy client is a private mirror of the host
        // player and must never appear as a player of its own — not in the
        // host's roster and never upstream at the master.
        if asProxy {
            let success = await processAsProxy(receivedModel, connectionId: event.connectionId)
            if success {
                await root.statisticsModel.record(receivedModel, direction: .incoming, origin: event.origin)
            }
            return success
        }

        if !receivedModel.sender.isMaster, receivedModel.sender.role != .notSet {
            if root.gameModel.add(playerId: receivedModel.sender.id, playerModel: receivedModel.sender.playerModel, sharingModel: SharingControlModel(id: receivedModel.sender.id, name: receivedModel.sender.name, show: true)) {
                await resetPlayers()
            }
        }

        guard let model = normalizedObserverMessage(receivedModel) else {
            // GameNetworkModel.debugDescription embeds sender.name — private. See CODE_AUDIT_Game §6.3.
            Logger.networking.debug("MasterController: Observer action ignored \(receivedModel.debugDescription, privacy: .private)")
            return true
        }

        if await shouldTrackPeerAvailabilitySource(model) {
            let recipients = root.logGameController.recipientIDs()
            gameModel.trackPeerAvailabilitySource(
                model,
                recipients: recipients
            )
        }

        let masterDeliveryAuthorizesAvailability = await recordDeliveryReceipt(model)
        if model.subType == .ok {
            let peerPresentationAuthorizesAvailability = if masterDeliveryAuthorizesAvailability {
                false
            } else {
                gameModel.acceptsPeerAvailabilityReceipt(model)
            }
            guard masterDeliveryAuthorizesAvailability || peerPresentationAuthorizesAvailability else {
                Logger.networking.debug("MasterController: Ignored uncorrelated availability acknowledgement from \(model.sender.id, privacy: .public)")
                await root.statisticsModel.record(model, direction: .incoming, origin: event.origin)
                return true
            }
        }

        do {
            try Task.checkCancellation()
            if let requestedData = try await handle(model, origin: event.origin) {
                try Task.checkCancellation()
                if requestedData.data != nil, requestedData.type != .map {
                    // The full payload went out — a later reshow can rely on
                    // the reference no matter which path delivered first.
                    // Map is deliberately excluded: all Map request responses
                    // are requester-only repairs (including photo-free generic
                    // updates). Only show(for:) publishes the full Map package
                    // to the group and may establish the shared sent baseline.
                    gameModel.markSentGameItem(type: requestedData.type, id: requestedData.id, version: requestedData.effectiveAssetVersion)
                }
                // Target the answer at the requester: an untargeted full payload
                // re-triggered "show" on every peer and flipped everyone's screen.
                await send(
                    type: model.type,
                    subtype: model.subType,
                    updated: requestedData,
                    origin: event.origin,
                    playerId: model.sender.id
                )
            }
            await root.statisticsModel.record(model, direction: .incoming, origin: event.origin)
            return true
        } catch is CancellationError {
            return false
        } catch {
            // GameNetworkModel.debugDescription embeds sender.name — private. See CODE_AUDIT_Game §6.3.
            Logger.networking.error("MasterController: Failed to process \(model.debugDescription, privacy: .private): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func shouldTrackPeerAvailabilitySource(
        _ model: GameNetworkModel
    ) async -> Bool {
        guard model.isPlayerFilePresentationEvent,
              GameNetworkModel.acceptsEventTimestamp(model.timestamp)
        else { return false }

        let baseline: Int
        switch model.data.type {
        case .photo:
            guard root.gameModel.gameControl.features.photoSharing else {
                return false
            }
            baseline = await root.photoRoot.gameControllable.networkVersion(
                for: model.data.id
            )
        case .pdf:
            baseline = await root.pdfRoot.gameControllable.networkVersion(
                for: model.data.id
            )
        case .space:
            guard root.gameModel.gameControl.features.spaceSharing else {
                return false
            }
            baseline = await root.spaceRoot.gameControllable.networkVersion(
                for: model.data.id
            )
        default:
            return false
        }
        return model.data.effectiveAssetVersion == baseline
    }

    /// Records every valid delivery acknowledgement, and returns whether the
    /// original master packet is a file-bearing reveal/store whose receipt may
    /// also update an asset-availability report.
    private func recordDeliveryReceipt(_ model: GameNetworkModel) async -> Bool {
        // A failed transfer and a request for missing bytes both prove the
        // opposite of delivery. Only an explicit successful acknowledgement
        // may complete the master's delivery row.
        guard model.subType == .ok else { return false }

        let deliveryID: GameDeliveryMessageID?
        if let replyToMessageID = model.replyToMessageID {
            deliveryID = gameModel.deliveryMessageID(replyingTo: replyToMessageID)
        } else if model.messageID == nil {
            // V1 has no stable wire identity. Retain its counter compatibility,
            // but only for an exact module/item receipt shape.
            deliveryID = root.gameModel.logData[model.counter]?.messageID
        } else {
            deliveryID = nil
        }

        guard let deliveryID else { return false }
        let deliveryMatch: (matches: Bool, authorizesAvailability: Bool)
        if let log = root.gameModel.logData[deliveryID.counter] {
            let matches = log.messageID == deliveryID &&
                log.type == model.type &&
                log.module == model.data.type &&
                log.itemId == model.data.id
            deliveryMatch = (
                matches: matches,
                authorizesAvailability: matches &&
                    (log.type == .reveal || log.type == .store)
            )
        } else {
            deliveryMatch = (matches: false, authorizesAvailability: false)
        }
        guard deliveryMatch.matches else { return false }

        let recorded = root.logGameController.updateMessage(
            messageID: deliveryID,
            player: model.sender.id
        )
        return recorded && deliveryMatch.authorizesAvailability
    }

    /// Observers participate in availability/repair handshakes but cannot issue
    /// gameplay actions. This is enforced again here even though the LAN bridge
    /// already refuses to relay observer group events.
    func normalizedObserverMessage(_ model: GameNetworkModel) -> GameNetworkModel? {
        guard model.sender.role == .observer else { return model }
        if model.isAcknowledgement { return model }

        // Reports and screen samples are safe only in their exact protocol
        // envelopes. Checking the subtype alone lets an observer pair a benign
        // action such as `.photoList` or `.screen` with `.reveal`, which then
        // enters a file-backed module's presentation path.
        switch (model.type, model.subType, model.data.type) {
        case (.update, .audioList, .audio),
             (.update, .photoList, .photo),
             (.update, .pdfList, .pdf),
             (.update, .spaceList, .space),
             (.store, .screen, .game):
            guard model.data.data != nil else { return nil }
            return model
        default:
            break
        }

        // An observer is a passive local-network display. It may name a missing
        // asset, but it can never upload bytes or disguise a gameplay action as
        // an asset request. Legacy data-less repair envelopes are normalized so
        // module handlers take their requester-only paths instead of presenting
        // the item to the group.
        guard model.data.data == nil,
              model.purpose == .assetRequest || model.purpose == .legacy
        else { return nil }

        let isPassiveAsset = switch model.data.type {
        case .audio, .dice, .map, .pdf, .photo, .space, .table, .weather:
            true
        default:
            false
        }
        guard isPassiveAsset else { return nil }

        let isRepairShape = switch (model.type, model.subType) {
        case (.reveal, .show), (.store, .store):
            true
        case (.reveal, .mapState):
            model.data.type == .map
        case (.update, .generic):
            model.data.type == .map
        default:
            false
        }
        guard isRepairShape else { return nil }

        var request = model
        request.purpose = .assetRequest
        request.audience = .master
        return request
    }
    
    func receivedFile(_ model: GameNetworkModel) async {
        Logger.networking.debug("MasterController: FILE Received \(model.counter, privacy: .public): \(model.type.debugDescription, privacy: .public) - \(model.subType.debugDescription, privacy: .public), \(model.data.type.token, privacy: .public) id: \(model.data.id, privacy: .public)")
        guard root.gameModel.gameConfig.isMaster != model.sender.isMaster else { return }
        guard await accepts(model, origin: .file) else { return }
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
        try await handle(
            model,
            origin: connectionId.map { GameMessageOrigin.direct($0) }
        )
    }

    private func handle(
        _ model: GameNetworkModel,
        origin: GameMessageOrigin?
    ) async throws -> NetworkCodableDataType? {
        switch model.data.type {
        case .adventure, .none, .rule, .setting, .editor, .generator, .search:
            // GameNetworkModel.debugDescription embeds sender.name — private. See CODE_AUDIT_Game §6.3.
            Logger.networking.error("MasterController: Request \(model.type.debugDescription, privacy: .public) but model request data is not supported. \(model.debugDescription, privacy: .private)")
            return nil
        case .audio:
            return try await handleAudio(model)
        case .dice:
            return try await handleDice(model)
        case .game:
            return try await handleGame(model)
        case .map:
            return try await handleMap(model, origin: origin)
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
            // GameNetworkModel.debugDescription embeds sender.name — private. See CODE_AUDIT_Game §6.3.
            Logger.networking.error("MasterController: Request \(model.type.debugDescription, privacy: .public) has an unrecognized module \(model.data.type.token, privacy: .public); ignoring. \(model.debugDescription, privacy: .private)")
            return nil
        }
    }

    func handleAudio(_ model: GameNetworkModel) async throws -> NetworkCodableDataType? {
        if model.subType == .ok {
            root.audioRoot.gameControllable.report(itemId: model.data.id, for: model.sender.id)
            await continuePendingAudioPlays()
            return nil
        }
        if model.subType == .failed {
            audioTransferFailed(itemId: model.data.id, playerId: model.sender.id)
            return nil
        }
        switch model.type {
        case .reveal, .store:
            return try await root.audioRoot.gameControllable.createGameData(for: model.data.id)
        case .update:
            switch model.subType {
            case .generic:
                guard root.gameModel.gameControl.features.audioSharing else { return nil }
                // Defend the master's own canonical copy first — mirrors
                // handlePhoto/handlePdf/handleSpace's `.itemMissing` import
                // fallback (this is also the legitimate path for a player
                // contributing a brand-new audio item the master has never
                // seen, exercised by PlayerMasterControllerTests.handleAudio).
                // The previous version of this fix unconditionally required
                // local data first, which blocked that legitimate case; the
                // actual vulnerability was importing an admitted player's
                // bytes over an *existing* master-owned copy with no check
                // at all — this restores that check. See CODE_AUDIT_Game §6.2.
                do {
                    let canonical = try await root.audioRoot.gameControllable.createGameData(for: model.data.id)
                    await send(type: .reveal, subtype: .show, updated: canonical)
                } catch ItemGameStorableError.itemMissing {
                    guard model.data.data != nil else { return nil }
                    try await root.audioRoot.gameControllable.updateGame(data: model.data, hide: false, deep: false)
                    await send(type: .reveal, subtype: .show, updated: model.data)
                } catch {
                    Logger.networking.error("MasterController: Failed to import shared audio \(model.data.id, privacy: .public) as canonical copy: \(error.localizedDescription, privacy: .public)")
                }
            case .playAudio:
                guard root.gameModel.gameControl.features.audioSharing else { return nil }
                await requestAudioPlay(model.data)
            case .audioList:
                guard applyAudioList(model) else { return nil }
                resetAudioTransfers(for: model.sender.id)
                let audioList = await root.audioRoot.audioGameControllable.audioList(allPlayers: true, with: root.gameModel.gameConfig.id)
                await send(type: .update, subtype: .audioList, updated: audioList)
                await continuePendingAudioPlays()
            default:
                break
            }
            return nil
        }
    }

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

    private func continuePendingAudioPlays() async {
        let pending = gameModel.pendingAudioPlays
        for (id, data) in pending {
            await fulfillPendingAudioPlay(id: id, data: data)
        }
    }

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
            if !stillMissing.isEmpty {
                // Audio repairs use GroupSessionJournal, whose attachment is
                // visible to the whole SharePlay session. Publishing the same
                // package once per missing logical player serializes duplicate
                // uploads and makes playback appear to hang. An untargeted
                // store is idempotent and also keeps Bonjour/local peers in
                // sync with a single transfer.
                await send(type: .store, subtype: .show, updated: audioData)
            }
        } catch {
            gameModel.audioTransferPlayers[id]?.subtract(newPlayers)
            Logger.networking.error("MasterController: Cannot prepare pending audio \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func audioTransferFailed(itemId: UUID, playerId: UUID) {
        gameModel.audioTransferPlayers[itemId]?.remove(playerId)
    }

    private func resetAudioTransfers(for playerId: UUID) {
        for itemId in gameModel.audioTransferPlayers.keys {
            gameModel.audioTransferPlayers[itemId]?.remove(playerId)
        }
    }

    private func broadcastAudioPlay(_ data: NetworkCodableDataType) async {
        await send(type: .update, subtype: .playAudio, updated: data)
        let hasLocalPlayer = root.networkStore.model.hasLocalPlayer
        if !hasLocalPlayer {
            // A failed playlist load/playback start used to be silently
            // swallowed here. See CODE_AUDIT_Game §4.2.
            do {
                try await root.audioRoot.audioGameControllable.play(with: data)
            } catch {
                Logger.networking.error("MasterController: Failed to start audio playback for \(data.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }
    
    func handleDice(_ model: GameNetworkModel) async throws -> NetworkCodableDataType? {
        guard model.subType != .ok && model.subType != .failed else { return nil }
        if model.senderType == .observer {
            guard model.purpose == .assetRequest,
                  model.data.data == nil,
                  model.type == .reveal || model.type == .store
            else { return nil }
            return try await root.diceRoot.gameControllable.createGameData(for: model.data.id)
        }

        switch model.type {
        case .reveal, .store:
            return try await root.diceRoot.gameControllable.createGameData(for: model.data.id)
        case .update:
            guard root.gameModel.gameControl.features.dicePlayers else { return nil }
            guard model.sender.isMaster || model.isPlayerDiceGroupEvent else { return nil }
            if let diceResult = DiceResultModel.decodeData(of: model.data.data) {
                root.battleRoundController.recordDiceResult(
                    diceResult,
                    senderId: model.sender.id,
                    isMaster: model.sender.isMaster
                )
            }
            let (_, resultCategory) = root.diceRoot.diceGameControllable.addGameDiceResult(
                data: model.data,
                name: model.senderName,
                supporterTier: model.sender.supporterTier,
                isGameMaster: model.sender.isMaster
            )
            if let diceResult = DiceResultModel.decodeData(of: model.data.data),
               let resultCategory {
                root.tableRoot.tableGameControllable.addResult(
                    resultCategory,
                    diceResult: diceResult
                )
            }
        }
        return nil
    }
    
    /// `.game`-typed envelopes carried a player-screenshot-sharing feature
    /// that had no UI consumer (a write path with no reader, growing
    /// `Data` per player for the session with no eviction) — removed.
    /// See CODE_AUDIT_Game §9.17. The dispatch case is kept as a no-op so an
    /// unrecognized/legacy `.game` message is silently ignored rather than
    /// logged as an error by the `@unknown default` path.
    func handleGame(_ model: GameNetworkModel) async throws -> NetworkCodableDataType? {
        nil
    }
    
    /// Test affordance — real dispatch always goes through `handle(_:origin:)`,
    /// which calls the `origin`-based overload below directly. Kept as the
    /// entry point the extensive `MapPlayerSequencingTests`/`MapMasterMessageFlowTests`
    /// suites already use. See CODE_AUDIT_Game §9.22.
    func handleMap(
        _ model: GameNetworkModel,
        connectionId: ConnectionController.ID? = nil
    ) async throws -> NetworkCodableDataType? {
        try await handleMap(
            model,
            origin: connectionId.map { GameMessageOrigin.direct($0) }
        )
    }

    private func handleMap(
        _ model: GameNetworkModel,
        origin: GameMessageOrigin?
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
                await sendFreshMapRecovery(recovery, origin: origin)
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
                    origin: origin,
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
                    origin: origin,
                    playerId: model.sender.id,
                    authoritativeMaster: true
                )
                await send(
                    type: .update,
                    subtype: .mapState,
                    updated: recovery.state,
                    origin: origin,
                    playerId: model.sender.id,
                    authoritativeMaster: true
                )
                if let battleUpdate = root.mapRoot.mapGameControllable.networkBattleRoundUpdate(
                    for: model.data.id
                ), root.mapRoot.mapGameControllable.battleRoundModel.isRunning {
                    await send(
                        type: .update,
                        subtype: .battleRound,
                        updated: battleUpdate,
                        origin: origin,
                        playerId: model.sender.id,
                        authoritativeMaster: true
                    )
                }
            } else {
                return recovery.full
            }
        case .store:
            break
        case .update:
            let observerContentRepair = model.senderType == .observer &&
                model.purpose == .assetRequest &&
                model.subType == .generic &&
                model.data.data == nil
            guard model.senderType != .observer || observerContentRepair else { return nil }
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
                        origin: origin
                    )
                    return nil
                }
                return update
            case .mapState:
                // never get from players mapState updates, only as resend from SharePlay?
                break
            case .mapPin:
                guard model.sender.role == .player,
                      model.purpose == .event,
                      model.effectiveAudience == .group
                else { return nil }
                if root.mapRoot.mapGameControllable.updatePinIfCurrentGeneration(
                    itemId: model.data.id,
                    data: model.data,
                    playerId: model.sender.id
                ) {
                    // `updatePinIfCurrentGeneration` never copies the sender's
                    // `healthPercent` (only location/isZoom/isHighlighted) —
                    // the master is the sole authority for it. Recomputing it
                    // here (e.g. a player highlighting a new target) only
                    // updates the master's own authoritative copy; without
                    // rebroadcasting, every player — including the one who
                    // just highlighted the pin — keeps showing the stale
                    // value until an unrelated battle action happens to
                    // broadcast next.
                    let syncResult = root.mapRoot.mapGameControllable.synchronizeBattleDefenders(
                        itemId: model.data.id,
                        isGameMaster: true
                    )
                    #if !os(tvOS)
                    root.gameModel.gameTableModel?.syncPawnsWithMapPins()
                    #endif
                    if syncResult.healthChanged {
                        await send(
                            type: .update,
                            subtype: .mapState,
                            updated: root.mapRoot.mapGameControllable.networkMapUpdate(for: model.data.id),
                            authoritativeMaster: true
                        )
                        if let battleUpdate = root.mapRoot.mapGameControllable.networkBattleRoundUpdate(
                            for: model.data.id
                        ) {
                            await send(
                                type: .update,
                                subtype: .battleRound,
                                updated: battleUpdate,
                                authoritativeMaster: true
                            )
                        }
                    }
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
        let mapControllable = root.mapRoot.mapGameControllable
        for _ in 0..<Self.maximumMapRecoveryCaptureAttempts {
            try Task.checkCancellation()
            let full: NetworkCodableDataType
            do {
                // Off-main starting point for the expensive capture — same
                // reasoning as the `createGameData(for:)` dispatcher above,
                // including cancellation propagation into the detached task.
                // See CODE_AUDIT_Game §3.5, CODE_AUDIT_9 §3.1.
                full = try await detachedGameData {
                    try await mapControllable.createMapGameData(for: itemId)
                }
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
            let state = root.mapRoot.mapGameControllable.networkMapUpdate(for: itemId)
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
        origin: GameMessageOrigin?
    ) async {
        // A changed generation is a new group intent for SharePlay. A direct LAN
        // requester can receive it on its exact connection without duplicating a
        // multi-part repair to every LAN peer.
        let deliveryOrigin: GameMessageOrigin? = if let origin, case .direct = origin {
            origin
        } else {
            nil
        }
        await send(
            type: .reveal,
            subtype: .show,
            updated: recovery.full,
            origin: deliveryOrigin,
            authoritativeMaster: true
        )
        await send(
            type: .update,
            subtype: .generic,
            updated: recovery.content,
            origin: deliveryOrigin,
            authoritativeMaster: true
        )
        await send(
            type: .update,
            subtype: .mapState,
            updated: recovery.state,
            origin: deliveryOrigin,
            authoritativeMaster: true
        )
    }

    /// Shared "player acknowledged a reveal" bookkeeping for the three
    /// file-backed modules (Pdf, Photo, Space) — handlePdf/handlePhoto/
    /// handleSpace's `.ok` branch previously hand-duplicated this exact
    /// sequence, differing only in which module's accessors they called.
    /// See CODE_AUDIT_10 §9.2.
    private func recordFileOkAck(
        _ model: GameNetworkModel,
        networkVersion: (_ itemId: UUID) async -> Int,
        setMasterVersion: (_ itemId: UUID, _ version: Int, _ masterId: UUID) -> Void,
        markAvailable: (_ itemId: UUID, _ version: Int, _ playerIds: [UUID], _ masterId: UUID) -> Void
    ) async {
        let masterId = root.gameModel.gameConfig.id
        let baseline = await networkVersion(model.data.id)
        setMasterVersion(model.data.id, baseline, masterId)
        markAvailable(model.data.id, model.data.effectiveAssetVersion, [model.sender.id], masterId)
    }

    /// Shared "apply an incoming file-version list" bookkeeping for the
    /// three file-backed modules — applyPdfList/applyPhotoList/
    /// applySpaceList below previously hand-duplicated this exact sequence,
    /// differing only in which module's accessors they called.
    /// See CODE_AUDIT_10 §9.2.
    private func applyFileList(
        _ model: GameNetworkModel,
        canApply: (_ senderId: UUID, _ counter: Int) -> Bool,
        apply: (_ data: NetworkCodableDataType, _ senderId: UUID, _ masterId: UUID, _ authoritative: Bool) async -> Bool,
        record: (_ counter: Int, _ senderId: UUID) -> Void
    ) async -> Bool {
        guard !model.sender.isMaster,
              canApply(model.sender.id, model.counter),
              await apply(model.data, model.sender.id, root.gameModel.gameConfig.id, false)
        else { return false }

        record(model.counter, model.sender.id)
        return true
    }

    func handlePdf(_ model: GameNetworkModel) async throws -> NetworkCodableDataType? {
        if model.subType == .ok {
            await recordFileOkAck(
                model,
                networkVersion: { await root.pdfRoot.gameControllable.networkVersion(for: $0) },
                setMasterVersion: { root.pdfRoot.pdfGameControllable.setMasterVersion(itemId: $0, version: $1, masterId: $2) },
                markAvailable: { root.pdfRoot.pdfGameControllable.markPdfAvailable(itemId: $0, version: $1, for: $2, masterId: $3) }
            )
            return nil
        }
        guard model.subType != .failed else { return nil }

        let masterId = root.gameModel.gameConfig.id
        if model.purpose == .assetRequest {
            guard model.type == .reveal || model.type == .store,
                  await root.pdfRoot.gameControllable.hasLocalFileData(for: model.data.id)
            else { return nil }
            return try await root.pdfRoot.gameControllable.createGameData(for: model.data.id)
        }

        switch model.type {
        case .reveal:
            let reference = await root.pdfRoot.gameControllable.share(id: model.data.id)
            root.pdfRoot.pdfGameControllable.setMasterVersion(
                itemId: reference.id,
                version: reference.effectiveAssetVersion,
                masterId: masterId
            )
            let senderIsAvailable = root.pdfRoot.pdfGameControllable.isPdfAvailable(
                itemId: model.data.id,
                for: model.sender.id,
                masterId: masterId
            )
            let matchesBaseline = model.data.effectiveAssetVersion == reference.effectiveAssetVersion

            if senderIsAvailable, matchesBaseline {
                if model.data.data != nil {
                    gameModel.markSentGameItem(
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

            // A mismatched sender with a master-owned baseline is a request
            // for that baseline, published as the authoritative group
            // reveal — a player's competing version of a known PDF never
            // replaces the master's own.
            guard await root.pdfRoot.gameControllable.hasLocalFileData(for: model.data.id) else { return nil }
            do {
                let canonical = try await root.pdfRoot.gameControllable.createGameData(for: model.data.id)
                gameModel.markSentGameItem(
                    type: .pdf,
                    id: canonical.id,
                    version: canonical.effectiveAssetVersion
                )
                await send(
                    type: .reveal,
                    subtype: .show,
                    updated: canonical,
                    replyToMessageID: model.messageID
                )
                return nil
            } catch ItemGameStorableError.itemMissing {
                // The master has no copy at all — there is no baseline to
                // defend. Mirror handlePhoto/handleSpace's `.itemMissing`
                // import fallback: import the player's bytes as the master's
                // own canonical copy, then relay exactly what was received.
                guard model.data.data != nil else { return nil }
                try await root.pdfRoot.gameControllable.updateGame(data: model.data, hide: false, deep: false)
                gameModel.markSentGameItem(
                    type: .pdf,
                    id: model.data.id,
                    version: model.data.effectiveAssetVersion
                )
                await send(
                    type: .reveal,
                    subtype: .show,
                    updated: model.data,
                    replyToMessageID: model.messageID
                )
                return nil
            } catch {
                Logger.networking.error("MasterController: Failed to import shared PDF \(model.data.id, privacy: .public) as canonical copy: \(error.localizedDescription, privacy: .public)")
                return nil
            }
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
                    gameModel.markSentGameItem(
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

    private func applyPdfList(_ model: GameNetworkModel) async -> Bool {
        await applyFileList(
            model,
            canApply: { gameModel.canApplyPdfList(from: $0, counter: $1) },
            apply: { data, senderId, masterId, authoritative in
                await root.pdfRoot.pdfGameControllable.applyPdfList(
                    data: data,
                    for: senderId,
                    with: masterId,
                    authoritative: authoritative
                )
            },
            record: { gameModel.recordPdfList(counter: $0, from: $1) }
        )
    }

    func handlePhoto(_ model: GameNetworkModel) async throws -> NetworkCodableDataType? {
        if model.subType == .ok {
            await recordFileOkAck(
                model,
                networkVersion: { await root.photoRoot.gameControllable.networkVersion(for: $0) },
                setMasterVersion: { root.photoRoot.photoGameControllable.setMasterVersion(itemId: $0, version: $1, masterId: $2) },
                markAvailable: { root.photoRoot.photoGameControllable.markPhotoAvailable(itemId: $0, version: $1, for: $2, masterId: $3) }
            )
            return nil
        }
        guard model.subType != .failed else { return nil }

        let masterId = root.gameModel.gameConfig.id
        if model.purpose == .assetRequest {
            guard model.type == .reveal || model.type == .store else { return nil }
            return try await root.photoRoot.gameControllable.createGameData(for: model.data.id)
        }

        switch model.type {
        case .reveal:
            guard root.gameModel.gameControl.features.photoSharing else { return nil }
            let reference = await root.photoRoot.gameControllable.share(id: model.data.id)
            root.photoRoot.photoGameControllable.setMasterVersion(
                itemId: reference.id,
                version: reference.effectiveAssetVersion,
                masterId: masterId
            )
            let senderIsAvailable = root.photoRoot.photoGameControllable.isPhotoAvailable(
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
                    gameModel.markSentGameItem(
                        type: .photo,
                        id: model.data.id,
                        version: reference.effectiveAssetVersion
                    )
                }
                await root.networkStore.sendLocalPlayer(model)
                return nil
            }

            // A mismatched sender with a master-owned baseline is a request
            // for that baseline, published as the authoritative group
            // reveal — a player's competing version of a known item never
            // replaces the master's own.
            do {
                let canonical = try await root.photoRoot.gameControllable.createGameData(for: model.data.id)
                gameModel.markSentGameItem(
                    type: .photo,
                    id: canonical.id,
                    version: canonical.effectiveAssetVersion
                )
                await send(
                    type: .reveal,
                    subtype: .show,
                    updated: canonical,
                    replyToMessageID: model.messageID
                )
                return nil
            } catch ItemGameStorableError.itemMissing {
                // The master has no copy at all — unlike a competing edit of
                // a known item, there is no baseline to defend. Mirror the
                // audio `.update/.generic` path: import the player's bytes as
                // the master's own canonical copy, then relay exactly what
                // was received so the group (and the master's own display)
                // converge on it without a redundant re-export round trip.
                guard model.data.data != nil else { return nil }
                try await root.photoRoot.gameControllable.updateGame(data: model.data, hide: false, deep: false)
                gameModel.markSentGameItem(
                    type: .photo,
                    id: model.data.id,
                    version: model.data.effectiveAssetVersion
                )
                await send(
                    type: .reveal,
                    subtype: .show,
                    updated: model.data,
                    replyToMessageID: model.messageID
                )
                return nil
            } catch {
                Logger.networking.error("MasterController: Failed to import shared photo \(model.data.id, privacy: .public) as canonical copy: \(error.localizedDescription, privacy: .public)")
                return nil
            }
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
                guard root.gameModel.gameControl.features.photoSharing else { return nil }
                if let canonical = try? await root.photoRoot.gameControllable.createGameData(for: model.data.id) {
                    gameModel.markSentGameItem(
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

    private func applyPhotoList(_ model: GameNetworkModel) async -> Bool {
        await applyFileList(
            model,
            canApply: { gameModel.canApplyPhotoList(from: $0, counter: $1) },
            apply: { data, senderId, masterId, authoritative in
                await root.photoRoot.photoGameControllable.applyPhotoList(
                    data: data,
                    for: senderId,
                    with: masterId,
                    authoritative: authoritative
                )
            },
            record: { gameModel.recordPhotoList(counter: $0, from: $1) }
        )
    }
    
    func handleTable(_ model: GameNetworkModel) async throws -> NetworkCodableDataType? {
        guard model.type != .update else { return nil }

        if model.subType == .ok {
            let currentVersion = await root.tableRoot.gameControllable.networkVersion(for: model.data.id)
            guard model.data.version != 0, model.data.version == currentVersion else { return nil }
            root.tableRoot.gameControllable.report(itemId: model.data.id, for: model.sender.id)
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
        if model.type == .update, model.subType == .valueUpdate {
            guard model.sender.role == .player,
                  model.purpose == .event,
                  model.effectiveAudience == .master,
                  let characterId = model.sender.characterId,
                  characterId == model.data.id,
                  // sender.characterId is otherwise self-declared, untrusted
                  // network input — every peer already sees every pin's
                  // characterId. See CODE_AUDIT_Game §6.1.
                  gameModel.isCharacterOwnershipAuthorized(senderId: model.sender.id, characterId: characterId),
                  let update = GameValueEntryUpdate.decodeData(of: model.data.data),
                  update.characterId == characterId,
                  root.gameModel.canApplyValueUpdate(
                      senderId: model.sender.id,
                      characterId: characterId,
                      entryId: update.entryId,
                      timestamp: model.timestamp
                  ),
                  root.characterRoot.valueGameControllable
                    .applyGameValueEntryUpdate(update) else {
                return nil
            }
            root.gameModel.recordValueUpdate(
                senderId: model.sender.id,
                characterId: characterId,
                entryId: update.entryId,
                timestamp: model.timestamp
            )
            return nil
        }

        // Character/Value messages have one normal-game purpose: synchronize
        // the selected Character when a player joins. Presentation, loot,
        // result, acknowledgement, and live-update variants are intentionally
        // unsupported until they get their own protocols.
        guard model.type == .update,
              model.subType == .store,
              model.senderType == .player,
              let characterId = model.sender.characterId,
              characterId == model.data.id,
              // The join handshake — binds this sender to characterId (or
              // confirms an existing binding). See CODE_AUDIT_Game §6.1.
              gameModel.bindCharacterOwnership(senderId: model.sender.id, characterId: characterId)
        else { return nil }

        if model.data.data == nil {
            let localVersion = await root.characterRoot.gameControllable.networkVersion(for: characterId)
            // Exact versions mean the master already owns this Character
            // package. Silence is the successful response; only a mismatch
            // asks the originating player for its potentially large package.
            guard localVersion != model.data.version else {
                root.mapRoot.mapGameControllable.setPlayerPin(
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
        root.mapRoot.mapGameControllable.setPlayerPin(
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
        guard let mapId = root.mapRoot.mapGameControllable.gameModel.currentItemId else {
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
            root.weatherRoot.gameControllable.report(itemId: model.data.id, for: model.sender.id)
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
            await recordFileOkAck(
                model,
                networkVersion: { await root.spaceRoot.gameControllable.networkVersion(for: $0) },
                setMasterVersion: { root.spaceRoot.spaceGameControllable.setMasterVersion(itemId: $0, version: $1, masterId: $2) },
                markAvailable: { root.spaceRoot.spaceGameControllable.markSpaceAvailable(itemId: $0, version: $1, for: $2, masterId: $3) }
            )
            return nil
        }
        guard model.subType != .failed else { return nil }

        let masterId = root.gameModel.gameConfig.id
        if model.purpose == .assetRequest {
            guard model.type == .reveal || model.type == .store,
                  await root.spaceRoot.gameControllable.hasLocalFileData(for: model.data.id)
            else { return nil }
            return try await root.spaceRoot.gameControllable.createGameData(for: model.data.id)
        }

        switch model.type {
        case .reveal:
            let playerSharingEnabled = root.gameModel.gameControl.features.spaceSharing
            let reference = await root.spaceRoot.gameControllable.share(id: model.data.id)
            root.spaceRoot.spaceGameControllable.setMasterVersion(
                itemId: reference.id,
                version: reference.effectiveAssetVersion,
                masterId: masterId
            )
            let senderIsAvailable = root.spaceRoot.spaceGameControllable.isSpaceAvailable(
                itemId: model.data.id,
                for: model.sender.id,
                masterId: masterId
            )
            let matchesBaseline = model.data.effectiveAssetVersion == reference.effectiveAssetVersion

            if playerSharingEnabled, senderIsAvailable, matchesBaseline {
                if model.data.data != nil {
                    gameModel.markSentGameItem(
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

            // A mismatched sender with a master-owned baseline is a request
            // for that baseline, published as the authoritative group
            // reveal — a player's competing version of a known Space never
            // replaces the master's own.
            do {
                let canonical = try await root.spaceRoot.gameControllable.createGameData(for: model.data.id)
                gameModel.markSentGameItem(
                    type: .space,
                    id: canonical.id,
                    version: canonical.effectiveAssetVersion
                )
                await send(
                    type: .reveal,
                    subtype: .show,
                    updated: canonical,
                    replyToMessageID: model.messageID
                )
                return nil
            } catch ItemGameStorableError.itemMissing {
                // The master has no copy at all — this is the player-sharing
                // path (`playerSharingEnabled` above), so unlike a competing
                // edit of a known Space, there is no baseline to defend.
                // Mirror handlePhoto/handleAudio's `.update/.generic` path:
                // import the player's bytes as the master's own canonical
                // copy, then relay exactly what was received so the group
                // (and the master's own display) converge on it without a
                // redundant re-export round trip.
                guard model.data.data != nil else { return nil }
                try await root.spaceRoot.gameControllable.updateGame(data: model.data, hide: false, deep: false)
                gameModel.markSentGameItem(
                    type: .space,
                    id: model.data.id,
                    version: model.data.effectiveAssetVersion
                )
                await send(
                    type: .reveal,
                    subtype: .show,
                    updated: model.data,
                    replyToMessageID: model.messageID
                )
                return nil
            } catch {
                Logger.networking.error("MasterController: Failed to import shared space \(model.data.id, privacy: .public) as canonical copy: \(error.localizedDescription, privacy: .public)")
                return nil
            }
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
                      model.purpose == .event,
                      model.effectiveAudience == .group,
                      root.gameModel.gameControl.features.spaceSharing,
                      root.spaceRoot.spaceGameControllable.isValidSpaceTransform(model.data)
                else { return nil }

                let baseline = await root.spaceRoot.gameControllable.networkVersion(for: model.data.id)
                root.spaceRoot.spaceGameControllable.setMasterVersion(
                    itemId: model.data.id,
                    version: baseline,
                    masterId: masterId
                )
                guard model.data.effectiveAssetVersion == baseline,
                      root.spaceRoot.spaceGameControllable.isSpaceAvailable(
                          itemId: model.data.id,
                          for: model.sender.id,
                          masterId: masterId
                      ),
                      gameModel.canApplySpaceTransform(
                          from: model.sender.id,
                          itemId: model.data.id,
                          version: baseline,
                          counter: model.counter
                      )
                else { return nil }

                guard root.spaceRoot.spaceGameControllable.applySpaceTransform(
                    data: model.data,
                    counter: model.counter,
                    timestamp: model.timestamp
                ) else { return nil }
                gameModel.recordSpaceTransform(
                    from: model.sender.id,
                    itemId: model.data.id,
                    version: baseline,
                    counter: model.counter
                )
            case .generic:
                // Compatibility with older players. Peer bytes never replace the
                // game master's canonical Space asset.
                guard root.gameModel.gameControl.features.spaceSharing else { return nil }
                if let canonical = try? await root.spaceRoot.gameControllable.createGameData(for: model.data.id) {
                    gameModel.markSentGameItem(
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

    private func applySpaceList(_ model: GameNetworkModel) async -> Bool {
        await applyFileList(
            model,
            canApply: { gameModel.canApplySpaceList(from: $0, counter: $1) },
            apply: { data, senderId, masterId, authoritative in
                await root.spaceRoot.spaceGameControllable.applySpaceList(
                    data: data,
                    for: senderId,
                    with: masterId,
                    authoritative: authoritative
                )
            },
            record: { gameModel.recordSpaceList(counter: $0, from: $1) }
        )
    }
}

// MARK: - MasterNetworkProxyControllerDelegate

extension MasterController: MasterNetworkProxyControllerDelegate {
    func lostProxy(for connectionId: ConnectionController.ID) async {
        Logger.networking.debug("MasterController: Lost Proxy for \(connectionId, privacy: .public)")
        _ = gameModel.remove(connectionId: connectionId)
    }

    func readyProxy(for connectionId: ConnectionController.ID) async {
        Logger.networking.debug("MasterController: Proxy Ready for \(connectionId, privacy: .public)")
        await replayCurrentPresentation(to: .proxy(connectionId))
        guard let characterId = root.gameModel.gamePlayer.characterId else { return }
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
    
    func receivedServerProxy(_ model: GameNetworkModel, connectionId: ConnectionController.ID) async {
        Logger.networking.debug("MasterController: Proxy Received \(model.counter, privacy: .public)/\(model.proxyCounter, privacy: .public): \(model.type.debugDescription, privacy: .public) - \(model.subType.debugDescription, privacy: .public), \(model.data.type.token, privacy: .public) id: \(model.data.id, privacy: .public)")
        await receivedProcess(model, origin: .proxy(connectionId))
    }
}

// MARK: - Proxy host routing

private extension MasterController {
    /// Routes a proxy client's message. The proxy device is a private mirror of
    /// the host player: nothing leaves this device with the proxy's identity,
    /// so the master and the other players never see it.
    func processAsProxy(
        _ model: GameNetworkModel,
        connectionId: ConnectionController.ID?
    ) async -> Bool {
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
            guard model.isDiceRollEvent else { return true }
            guard root.gameModel.gameControl.features.dicePlayers else { return true }
            // The proxy rolls as the host player — show it on the host as well.
            let hostName = root.gameModel.gamePlayer.name
            let hostSupporterTier = root.gameModel.gamePlayer.supporterTier
            _ = root.diceRoot.diceGameControllable.addGameDiceResult(
                data: model.data,
                name: hostName,
                supporterTier: hostSupporterTier,
                isGameMaster: false
            )
            await root.gameModel.playerController?.relayProxyGroupEvent(
                model,
                excludingProxyConnection: connectionId
            )
            return true
        }

        if model.data.type == .map,
           model.type == .update,
           model.subType == .mapPin,
           model.purpose == .event {
            // Update the host's own map first, then tell the master.
            let hostId = root.gameModel.gameConfig.id
            guard root.mapRoot.mapGameControllable.updatePinIfCurrentGeneration(
                itemId: model.data.id,
                data: model.data,
                playerId: hostId
            ) else {
                return true
            }
            await root.gameModel.playerController?.relayProxyGroupEvent(
                model,
                excludingProxyConnection: connectionId
            )
            return true
        }

        if model.data.type == .space,
           model.type == .update,
           model.subType == .spaceTransform,
           model.purpose == .event {
            guard root.gameModel.gameControl.features.spaceSharing,
                  root.spaceRoot.spaceGameControllable.isValidSpaceTransform(model.data),
                  await root.spaceRoot.gameControllable.networkVersion(for: model.data.id) == model.data.effectiveAssetVersion,
                  root.spaceRoot.spaceGameControllable.applySpaceTransform(
                      data: model.data,
                      counter: model.counter,
                      timestamp: model.timestamp
                  )
            else { return true }
            await root.gameModel.playerController?.relayProxyGroupEvent(
                model,
                excludingProxyConnection: connectionId
            )
            return true
        }

        if model.purpose == .event,
           model.type == .reveal,
           model.subType == .show,
           (model.data.type == .photo || model.data.type == .pdf || model.data.type == .space) {
            guard let playerController = root.gameModel.playerController else {
                await remapUpstream(model)
                return true
            }
            // One host envelope drives all three destinations: upstream, the
            // co-located player, and sibling mirrors. Excluding the source
            // connection prevents an echo receipt from the initiating mirror.
            await playerController.relayProxyPresentation(
                model,
                excludingProxyConnection: connectionId
            )
            return true
        }

        if model.purpose == .assetRequest {
            if await canServeProxyRequest(for: model.data) {
                do {
                    // Serve from the host's own game memory — local network is
                    // fast and the master never learns about the proxy.
                    // `authoritativeMaster` mirrors replayCurrentPresentation:
                    // the proxy's handlers only accept reveals from the master.
                    if let requestedData = try await proxyRepairData(
                        for: model,
                        connectionId: connectionId
                    ) {
                        await send(
                            type: model.type,
                            subtype: model.subType,
                            updated: requestedData,
                            connectionId: connectionId,
                            playerId: model.sender.id,
                            authoritativeMaster: true
                        )
                    }
                    return true
                } catch {
                    // GameNetworkModel.debugDescription embeds sender.name — private. See CODE_AUDIT_Game §6.3.
                    Logger.networking.error("MasterController: Cannot serve proxy request locally \(model.debugDescription, privacy: .private): \(error.localizedDescription, privacy: .public)")
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

    /// Asset requests bypass the normal peer-presentation handlers. Those
    /// handlers intentionally publish a player's reveal to the group, whereas
    /// a proxy repair must return the host's bytes only to the requesting
    /// private mirror.
    func proxyRepairData(
        for model: GameNetworkModel,
        connectionId: ConnectionController.ID?
    ) async throws -> NetworkCodableDataType? {
        switch model.data.type {
        case .audio:
            return try await root.audioRoot.gameControllable.createGameData(for: model.data.id)
        case .photo:
            return try await root.photoRoot.gameControllable.createGameData(for: model.data.id)
        case .pdf:
            return try await root.pdfRoot.gameControllable.createGameData(for: model.data.id)
        case .space:
            return try await root.spaceRoot.gameControllable.createGameData(for: model.data.id)
        default:
            return try await handle(model, connectionId: connectionId)
        }
    }

    /// Re-sends a proxy client's message as the host player's own — fresh host
    /// counter, host sender identity, same payload.
    func remapUpstream(_ model: GameNetworkModel) async {
        guard let playerController = root.gameModel.playerController else {
            // GameNetworkModel.debugDescription embeds sender.name — private. See CODE_AUDIT_Game §6.3.
            Logger.networking.error("MasterController: No player controller to remap proxy message \(model.debugDescription, privacy: .private)")
            return
        }
        // This message came from a proxy client. Sending it upstream must not
        // broadcast the request back to that same proxy (or its siblings),
        // otherwise every mirror can request the same missing payload again.
        await playerController.send(
            type: model.type,
            subType: model.subType,
            updated: model.data,
            relayToProxyClients: false,
            purpose: model.purpose
        )
    }

    /// Whether the host holds everything needed to answer a proxy data request
    /// itself, including the binaries of file-backed modules.
    func canServeProxyRequest(for data: NetworkCodableDataType) async -> Bool {
        switch data.type {
        case .photo:
            guard await root.photoRoot.gameControllable.hasLocalFileData(for: data.id) else { return false }
            return await root.photoRoot.gameControllable.networkVersion(for: data.id) == data.effectiveAssetVersion
        case .pdf:
            guard await root.pdfRoot.gameControllable.hasLocalFileData(for: data.id) else { return false }
            return await root.pdfRoot.gameControllable.networkVersion(for: data.id) == data.effectiveAssetVersion
        case .audio:
            guard await root.audioRoot.audioGameControllable.hasLocalAudioData(for: data.id) else { return false }
            return await root.audioRoot.gameControllable.networkVersion(for: data.id) == data.effectiveAssetVersion
        case .space:
            guard await root.spaceRoot.gameControllable.hasLocalFileData(for: data.id) else { return false }
            return await root.spaceRoot.gameControllable.networkVersion(for: data.id) == data.effectiveAssetVersion
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
            return root.weatherRoot.weatherGameControllable.isWeatherAvailable(
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
    func replayCurrentPresentation(to origin: GameMessageOrigin) async {
        guard let presentation = root.gameModel.playerController?.gameModel.gameUpdateType else { return }

        let reference: NetworkCodableDataType?
        switch presentation {
        case .map:
            reference = if let id = root.mapRoot.gameControllable.gameModel.currentItemId {
                await root.mapRoot.mapGameControllable.shareMap(id: id)
            } else {
                nil
            }
        case .pdf:
            reference = if let id = root.pdfRoot.gameControllable.gameModel.currentItemId {
                await root.pdfRoot.gameControllable.share(id: id)
            } else {
                nil
            }
        case .photo:
            reference = if let id = root.photoRoot.gameControllable.gameModel.currentItemId {
                await root.photoRoot.gameControllable.share(id: id)
            } else {
                nil
            }
        case .table:
            // Tables are Messenger-only. Without a SharePlay replay, a late
            // participant could finish Journal synchronization by showing an
            // older Photo/Map even though the current screen is a Table. Keep
            // the existing LAN/proxy reconnect policy, but send the master's
            // canonical Table reference to the newly active SharePlay peer.
            reference = if case .sharePlay = origin,
                           let id = root.tableRoot.gameControllable.gameModel.currentItemId {
                await root.tableRoot.gameControllable.share(id: id)
            } else {
                nil
            }
        case .value:
            // Values are not presentations. A proxy receives the host's full
            // Character through readyProxy(for:) immediately below instead.
            reference = nil
        case .weather:
            reference = if let id = root.weatherRoot.gameControllable.gameModel.currentItemId {
                await root.weatherRoot.weatherGameControllable.shareWeather(id: id)
            } else {
                nil
            }
        case .space:
            reference = if let id = root.spaceRoot.gameControllable.gameModel.currentItemId {
                await root.spaceRoot.gameControllable.share(id: id)
            } else {
                nil
            }
        default:
            reference = nil
        }

        guard let reference else { return }
        let replayReference = Self.presentationReplayReference(reference, origin: origin)
        await send(
            type: .reveal,
            subtype: .show,
            updated: replayReference,
            origin: origin,
            authoritativeMaster: true
        )
        if presentation == .map {
            let mapUpdate = await root.mapRoot.mapGameControllable.networkMapContentUpdate(for: reference.id)
            await send(
                type: .update,
                subtype: .generic,
                updated: mapUpdate,
                origin: origin,
                authoritativeMaster: true
            )
            let mapState = root.mapRoot.mapGameControllable.networkMapUpdate(for: reference.id)
            await send(
                type: .update,
                subtype: .mapState,
                updated: mapState,
                origin: origin,
                authoritativeMaster: true
            )
        } else if presentation == .space,
                  let transformReplay = root.spaceRoot.spaceGameControllable.latestSpaceTransformReplay(
                      for: reference.id,
                      version: reference.effectiveAssetVersion
                  ) {
            // Messenger transforms have no history. Replay the retained pose
            // after the asset reference; the Space viewer also retains it while
            // the file-backed entity is still loading.
            await send(
                type: .update,
                subtype: .spaceTransform,
                updated: transformReplay.data,
                timestamp: transformReplay.timestamp,
                appliesLocalSpaceTransform: false,
                origin: origin,
                authoritativeMaster: true
            )
        }
    }
}

extension MasterController {
    /// A late SharePlay participant already receives the current Journal
    /// snapshot. Replay only Weather's canonical identity over Messenger so the
    /// replay is physically targeted and cannot replace the session-wide
    /// Journal attachment. If that participant missed the bytes, its normal
    /// availability check requests the full package from the master.
    static func presentationReplayReference(
        _ reference: NetworkCodableDataType,
        origin: GameMessageOrigin
    ) -> NetworkCodableDataType {
        guard case .sharePlay = origin,
              reference.type == .weather,
              reference.data != nil
        else { return reference }

        return NetworkCodableDataType(
            id: reference.id,
            type: reference.type,
            version: reference.version,
            assetVersion: reference.assetVersion,
            contentVersion: reference.contentVersion
        )
    }
}
