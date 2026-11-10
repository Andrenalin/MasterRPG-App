// @copyright André Trettin

import CoreRPG
import Foundation

@MainActor @Observable
final class MasterControllerModel {
    private struct SpaceTransformSequenceKey: Hashable, Sendable {
        let playerId: UUID
        let itemId: UUID
        let version: Int
    }

    /// What the master sent under a counter, so an acknowledgement is matched to its message
    /// without the display log: that log keeps only the newest rows, and a receipt for an evicted
    /// row would otherwise be dropped. See CODE_AUDIT_Game_Shareplay §5.8.
    struct SentDelivery: Equatable, Sendable {
        let type: RPGMessageType
        let module: NetworkModules
        let itemId: UUID
    }
    static let maximumSentDeliveries = 4096
    private var sentDeliveries: [Int: SentDelivery] = [:]
    private var sentDeliveryOrder: [Int] = []

    func recordSentDelivery(counter: Int, type: RPGMessageType, module: NetworkModules, itemId: UUID) {
        guard sentDeliveries.updateValue(SentDelivery(type: type, module: module, itemId: itemId), forKey: counter) == nil else { return }
        sentDeliveryOrder.append(counter)
        while sentDeliveryOrder.count > Self.maximumSentDeliveries {
            sentDeliveries[sentDeliveryOrder.removeFirst()] = nil
        }
    }

    func sentDelivery(counter: Int) -> SentDelivery? {
        sentDeliveries[counter]
    }

    var messageCounter: Int = 1
    /// The counter of the newest item the game master showed. A show whose package is still
    /// being built when a newer one starts is superseded. See CODE_AUDIT_Game_Shareplay §5.29.
    var latestShownCounter = 0
    /// The delivery namespace of this game's message log. A restarted game counts from one
    /// again and must not complete a row of the game before it.
    let deliverySessionId = UUID()
    /// Audio a play was asked for while a player still lacks its file. Playback starts once
    /// every player reported it.
    var pendingAudioPlays: [UUID: NetworkCodableDataType] = [:]
    /// Number of retries already attempted per pending audio play, so a
    /// permanently failing export stops retrying instead of resurrecting
    /// itself every `audioPlayRetryDelay` for the rest of the session.
    /// See CODE_AUDIT_17 §3.6.
    var audioPlayRetryAttempts: [UUID: Int] = [:]
    /// The players given up on for an audio item. A package is not sent again to a player that
    /// failed to import it: one the player could not load through the Journal (it stayed
    /// suspended until the deadline) stalled again when sent again, and held up the player's
    /// other downloads. The play goes on without that player.
    private var abandonedAudioDeliveries: Set<AudioDeliveryKey> = []
    /// The deliveries sent a second time after the player reported a failed import. The first
    /// failure earns one more try, the second one the abandon. See CODE_AUDIT_Game_Photo_Audio §5.2.
    private var retriedAudioDeliveries: Set<AudioDeliveryKey> = []

    private struct AudioDeliveryKey: Hashable, Sendable {
        let itemId: UUID
        let playerId: UUID
    }
    /// The content version of each map as the players last got it. A map state for another
    /// content version is preceded by the content: revealing a room changes what the players
    /// may read of it, and only the content update carries that text.
    var sentMapContentVersions: [UUID: Int] = [:]
    /// The packages exported last, reused for every player that asks for the same item.
    /// See `MasterPackageCache`.
    var packageCache = MasterPackageCache()
    /// Orders the game master's map photo changes (the presentation itself lives in the game
    /// master's own screen state, see `MasterController+MapPhoto.swift`) and table weather
    /// changes (see `MasterController+TableWeather.swift`).
    private var sequences = MasterSequenceSource()
    /// The order of the availability lists of every player. See `ListSequenceTracker`.
    private var listSequence = ListSequenceTracker()
    private var lastSpaceTransformCounters: [SpaceTransformSequenceKey: Int] = [:]

    /// Which Character id each sender is authorized to act on — established
    /// once at that sender's join handshake and enforced on every later
    /// `.value` message. `sender.characterId` is otherwise self-declared,
    /// untrusted network input every peer can already read off the wire
    /// (encoded in `.mapState`). See CODE_AUDIT_Game §6.1.
    private var characterOwnership: [UUID: UUID] = [:]

    /// A `.valueUpdate` that arrived before its sender's ownership binding
    /// was established — held so `bindCharacterOwnership`'s caller can
    /// replay it once the join handshake lands, instead of the edit being
    /// silently dropped by a message-ordering race. See CODE_AUDIT_Network §5.18.
    ///
    /// Held per sender in arrival order, the newest per entry: an update is for one entry, so
    /// the single slot per sender lost a change of hit points to a later change of another
    /// value. Bounded per sender; the oldest goes first. See CODE_AUDIT_21 §5.9.
    private var pendingValueUpdatesAwaitingOwnership: [UUID: [PendingValueUpdate]] = [:]

    private struct PendingValueUpdate {
        /// The entry the update is for, `nil` when the payload does not decode (it is then
        /// kept as it is and rejected on replay).
        let entryId: UUID?
        let model: GameNetworkModel
    }

    /// Updates held per sender before the handshake. A Character sheet has a few dozen values.
    static let maximumPendingValueUpdatesPerSender = 32

    func deferValueUpdateAwaitingOwnership(_ model: GameNetworkModel) {
        let entryId = GameValueEntryUpdate.decodeData(of: model.data.data)?.entryId
        var pending = pendingValueUpdatesAwaitingOwnership[model.sender.id, default: []]
        if let entryId {
            pending.removeAll { $0.entryId == entryId }
        }
        pending.append(PendingValueUpdate(entryId: entryId, model: model))
        if pending.count > Self.maximumPendingValueUpdatesPerSender {
            pending.removeFirst(pending.count - Self.maximumPendingValueUpdatesPerSender)
        }
        pendingValueUpdatesAwaitingOwnership[model.sender.id] = pending
    }

    /// Removes and returns the deferred `.valueUpdate`s of `senderId`, in counter order.
    /// Call once `bindCharacterOwnership` succeeds for that sender.
    @discardableResult
    func takePendingValueUpdates(senderId: UUID) -> [GameNetworkModel] {
        (pendingValueUpdatesAwaitingOwnership.removeValue(forKey: senderId) ?? [])
            .map(\.model)
            .sorted { $0.counter < $1.counter }
    }

    /// INTENDED (CODE_AUDIT_17 §6.1, won't fix): the claimed id may be an existing Character
    /// on the master — players update their Character this way. Access is gated at connection
    /// time (PIN / GM-approved / SharePlay call), so do not add a library-existence check here.
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

    /// Whether a sender plays `characterId` as its own Character. A companion package may
    /// never write such a Character.
    func isCharacterBound(_ characterId: UUID) -> Bool {
        characterOwnership.values.contains(characterId)
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

    /// The sequence of the game master's next table weather change.
    func nextTableWeatherSequence() -> Int {
        sequences.next(.tableWeather)
    }

    /// The sequence of the game master's next map photo change.
    func nextMapPhotoSequence() -> Int {
        sequences.next(.mapPhoto)
    }

    /// Reserves the next counter atomically. Reading and incrementing in separate
    /// calls lets concurrent sends stamp the same counter, which the receivers'
    /// deduplication then treats as one message.
    func nextMessageCounter() -> Int {
        defer { messageCounter += 1 }
        return messageCounter
    }

    /// Forgets what was kept for a player that left.
    func forget(playerId: UUID) {
        listSequence.forget(senderId: playerId)
        abandonedAudioDeliveries = abandonedAudioDeliveries.filter { $0.playerId != playerId }
        retriedAudioDeliveries = retriedAudioDeliveries.filter { $0.playerId != playerId }
        // Every start of a game mints a new sender id, so a player that rejoins would meet its own
        // old binding on its Character and be refused for good. See CODE_AUDIT_Audio2 §5.2.
        characterOwnership[playerId] = nil
        lastSpaceTransformCounters = lastSpaceTransformCounters.filter { $0.key.playerId != playerId }
        // Otherwise a `.valueUpdate` deferred while waiting for this sender's ownership
        // binding stays queued forever once the sender disconnects before that binding
        // ever lands, and would incorrectly replay against a future, unrelated sender
        // that reuses the same id. See CODE_AUDIT_17 §5.25.
        pendingValueUpdatesAwaitingOwnership.removeValue(forKey: playerId)
    }

    func isAudioDeliveryAbandoned(itemId: UUID, playerId: UUID) -> Bool {
        abandonedAudioDeliveries.contains(AudioDeliveryKey(itemId: itemId, playerId: playerId))
    }

    /// Gives up on `playerId` for `itemId`: its import failed, or the pending play's deadline
    /// passed.
    func abandonAudioDelivery(itemId: UUID, playerId: UUID) {
        abandonedAudioDeliveries.insert(AudioDeliveryKey(itemId: itemId, playerId: playerId))
    }

    /// Whether the failed delivery of `itemId` to `playerId` may be sent once more. Answers `true`
    /// once per delivery and remembers it.
    func claimAudioDeliveryRetry(itemId: UUID, playerId: UUID) -> Bool {
        retriedAudioDeliveries.insert(AudioDeliveryKey(itemId: itemId, playerId: playerId)).inserted
    }

    func resetAudioDeliveryFailures() {
        abandonedAudioDeliveries.removeAll()
        retriedAudioDeliveries.removeAll()
    }

    func canApplyList(_ module: NetworkModules, from playerId: UUID, counter: Int) -> Bool {
        listSequence.canApply(module, from: playerId, counter: counter)
    }

    func recordList(_ module: NetworkModules, counter: Int, from playerId: UUID) {
        listSequence.record(module, counter: counter, from: playerId)
    }

    func resetListSequences() {
        listSequence.reset()
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
