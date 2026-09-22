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
    // Bounded like every sibling per-connection cache below (256, matching
    // `maximumPlayerJournalAdmissions`/`maximumPeerAvailabilitySources`) —
    // previously an unbounded `Set` that only ever grew for the life of the
    // game, since a LAN/proxy id is never reinstated (only a SharePlay
    // participant UUID is, per `reinstateConnection`'s own doc). See
    // CODE_AUDIT_Reconnect §7.1, §9.2.
    private var retiredConnectionIDs = PhysicalIdentityDenylist<ConnectionController.ID>(capacity: 256)
    let deliverySessionID = UUID()
    private var deliveryMessagesByWireID: [UUID: GameDeliveryMessageID] = [:]
    private var deliveryMessagesByWireIDOrder: [UUID] = []
    private static let maximumDeliveryMessagesByWireID = 256
    var asProxy = false
    var pendingAudioPlays: [UUID: NetworkCodableDataType] = [:]
    var audioTransferPlayers: [UUID: Set<UUID>] = [:]
    /// Number of retries already attempted per pending audio play, so a
    /// permanently failing export stops retrying instead of resurrecting
    /// itself every `audioPlayRetryDelay` for the rest of the session.
    /// See CODE_AUDIT_17 §3.6.
    var audioPlayRetryAttempts: [UUID: Int] = [:]
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

    /// A `.valueUpdate` that arrived before its sender's ownership binding
    /// was established — held so `bindCharacterOwnership`'s caller can
    /// replay it once the join handshake lands, instead of the edit being
    /// silently dropped by a message-ordering race. One slot per sender: a
    /// later update superseding an unreplayed one only needs the latest
    /// replayed. See CODE_AUDIT_Network §5.18.
    private var pendingValueUpdatesAwaitingOwnership: [UUID: GameNetworkModel] = [:]

    func deferValueUpdateAwaitingOwnership(_ model: GameNetworkModel) {
        pendingValueUpdatesAwaitingOwnership[model.sender.id] = model
    }

    /// Removes and returns a deferred `.valueUpdate` for `senderId`, if any.
    /// Call once `bindCharacterOwnership` succeeds for that sender.
    @discardableResult
    func takePendingValueUpdate(senderId: UUID) -> GameNetworkModel? {
        pendingValueUpdatesAwaitingOwnership.removeValue(forKey: senderId)
    }

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
        pendingValueUpdatesAwaitingOwnership.removeAll()
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
        // Otherwise a `.valueUpdate` deferred while waiting for this sender's ownership
        // binding stays queued forever once the sender disconnects before that binding
        // ever lands, and would incorrectly replay against a future, unrelated sender
        // that reuses the same id. See CODE_AUDIT_17 §5.25.
        pendingValueUpdatesAwaitingOwnership.removeValue(forKey: playerId)
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
        deferredPlayerJournalFiles.removeAll()
        deferredPlayerJournalFileOrder.removeAll()
    }

    private func removePlayerJournalAdmissions(for playerId: UUID) {
        playerJournalAdmissions = playerJournalAdmissions.filter {
            $0.key.senderId != playerId
        }
        playerJournalAdmissionOrder.removeAll { $0.senderId == playerId }
        deferredPlayerJournalFiles = deferredPlayerJournalFiles.filter {
            $0.key.senderId != playerId
        }
        deferredPlayerJournalFileOrder.removeAll { $0.senderId == playerId }
    }

    /// A player Journal file event whose admission couldn't yet be confirmed
    /// — the matching Messenger admission metadata (see
    /// `admitPlayerJournalMetadata`) hadn't arrived yet. GroupSessionJournal
    /// attachments and GroupSessionMessenger messages are independent
    /// channels with no cross-channel ordering guarantee, so this is held
    /// and replayed once the matching admission lands, instead of the file
    /// being lost permanently. See CODE_AUDIT_Network §5.16.
    private var deferredPlayerJournalFiles: [PlayerJournalAdmissionKey: GameNetworkModel] = [:]
    private var deferredPlayerJournalFileOrder: [PlayerJournalAdmissionKey] = []
    private static let maximumDeferredPlayerJournalFiles = 64

    func deferUnmatchedPlayerJournalFile(_ model: GameNetworkModel) {
        guard let messageId = model.messageID else { return }
        let key = PlayerJournalAdmissionKey(senderId: model.sender.id, messageId: messageId)
        if deferredPlayerJournalFiles[key] == nil {
            deferredPlayerJournalFileOrder.append(key)
            while deferredPlayerJournalFileOrder.count > Self.maximumDeferredPlayerJournalFiles {
                deferredPlayerJournalFiles[deferredPlayerJournalFileOrder.removeFirst()] = nil
            }
        }
        deferredPlayerJournalFiles[key] = model
    }

    /// Removes and returns a deferred player Journal file event matching
    /// `senderId`/`messageId`, if any. Call once `admitPlayerJournalMetadata`
    /// newly records a matching admission.
    func takeDeferredPlayerJournalFile(senderId: UUID, messageId: UUID?) -> GameNetworkModel? {
        guard let messageId else { return nil }
        let key = PlayerJournalAdmissionKey(senderId: senderId, messageId: messageId)
        guard let model = deferredPlayerJournalFiles.removeValue(forKey: key) else { return nil }
        deferredPlayerJournalFileOrder.removeAll { $0 == key }
        return model
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
    ///
    /// Declared here (not `private`) because it is read and written only from
    /// `MasterController+Control.swift`'s `resetPlayers()`/`stop()`, a
    /// different file from this declaration.
    var resetPlayersTask: Task<Void, Never>?

    /// Bounded per-item retry after `fulfillPendingAudioPlay` fails to
    /// prepare a missing player's copy (e.g. a transient export error).
    /// Without this, nothing schedules another attempt unless an unrelated
    /// event (another player's ack, a roster reset) happens to call
    /// `continuePendingAudioPlays()` again, and the queued play could
    /// otherwise never reach that player for the rest of the session.
    /// Declared here (not `private`) because it is read and written only
    /// from `MasterController+AudioMessages.swift`, a different file from
    /// this declaration — same rationale as `resetPlayersTask`. See
    /// CODE_AUDIT_Network §5.13.
    var audioPlayRetryTasks: [UUID: Task<Void, Never>] = [:]

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

// Empty conformance declaration kept in the same file as the class itself — Swift requires a
// class's `Sendable` conformance (inherited here via `MasterNetworkStoreDelegate: Sendable`) to
// be declared alongside the class, even though the actual protocol requirements are implemented
// in `MasterController+NetworkStoreDelegate.swift`.
extension MasterController: MasterNetworkStoreDelegate {}
