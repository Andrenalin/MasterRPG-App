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

    var messageCounter: Int = 1
    /// The delivery namespace of this game's message log. A restarted game counts from one
    /// again and must not complete a row of the game before it.
    let deliverySessionID = UUID()
    var asProxy = false
    /// Audio a play was asked for while a player still lacks its file. Playback starts once
    /// every player reported it.
    var pendingAudioPlays: [UUID: NetworkCodableDataType] = [:]
    /// Number of retries already attempted per pending audio play, so a
    /// permanently failing export stops retrying instead of resurrecting
    /// itself every `audioPlayRetryDelay` for the rest of the session.
    /// See CODE_AUDIT_17 §3.6.
    var audioPlayRetryAttempts: [UUID: Int] = [:]
    /// The content version of each map as the players last got it. A map state for another
    /// content version is preceded by the content: revealing a room changes what the players
    /// may read of it, and only the content update carries that text.
    var sentMapContentVersions: [UUID: Int] = [:]
    /// Orders the game master's map photo changes. The presentation itself lives in the game
    /// master's own screen state. See `MasterController+MapPhoto.swift`.
    private var mapPhotoSequence = 0
    private var lastAudioListCounters: [UUID: Int] = [:]
    private var lastPhotoListCounters: [UUID: Int] = [:]
    private var lastPdfListCounters: [UUID: Int] = [:]
    private var lastSpaceListCounters: [UUID: Int] = [:]
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

    /// The sequence of the game master's next map photo change.
    func nextMapPhotoSequence() -> Int {
        mapPhotoSequence += 1
        return mapPhotoSequence
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
        lastAudioListCounters[playerId] = nil
        lastPhotoListCounters[playerId] = nil
        lastPdfListCounters[playerId] = nil
        lastSpaceListCounters[playerId] = nil
        lastSpaceTransformCounters = lastSpaceTransformCounters.filter { $0.key.playerId != playerId }
        // Otherwise a `.valueUpdate` deferred while waiting for this sender's ownership
        // binding stays queued forever once the sender disconnects before that binding
        // ever lands, and would incorrectly replay against a future, unrelated sender
        // that reuses the same id. See CODE_AUDIT_17 §5.25.
        pendingValueUpdatesAwaitingOwnership.removeValue(forKey: playerId)
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
