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

    var messageCounter: Int = 1
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
    /// How often a player failed to import an audio package, per item. See
    /// `recordAudioDeliveryFailure`.
    private var audioDeliveryFailures: [AudioDeliveryKey: Int] = [:]
    /// Times the master sends an audio package again to a player that failed to import it.
    static let maximumAudioDeliveryRetries = 3

    private struct AudioDeliveryKey: Hashable, Sendable {
        let itemId: UUID
        let playerId: UUID
    }
    /// The content version of each map as the players last got it. A map state for another
    /// content version is preceded by the content: revealing a room changes what the players
    /// may read of it, and only the content update carries that text.
    var sentMapContentVersions: [UUID: Int] = [:]
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
        audioDeliveryFailures = audioDeliveryFailures.filter { $0.key.playerId != playerId }
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

    /// Counts a failed import of `itemId` on `playerId`. Returns whether the package should be
    /// sent again (`false`: the player is given up on, see `isAudioDeliveryAbandoned`).
    func recordAudioDeliveryFailure(itemId: UUID, playerId: UUID) -> Bool {
        let key = AudioDeliveryKey(itemId: itemId, playerId: playerId)
        let failures = (audioDeliveryFailures[key] ?? 0) + 1
        audioDeliveryFailures[key] = failures
        return failures <= Self.maximumAudioDeliveryRetries
    }

    func isAudioDeliveryAbandoned(itemId: UUID, playerId: UUID) -> Bool {
        (audioDeliveryFailures[AudioDeliveryKey(itemId: itemId, playerId: playerId)] ?? 0) > Self.maximumAudioDeliveryRetries
    }

    func resetAudioDeliveryFailures() {
        audioDeliveryFailures.removeAll()
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
