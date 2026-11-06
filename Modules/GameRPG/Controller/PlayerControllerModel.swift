// @copyright André Trettin

import CoreRPG
import Foundation
import MapRPG

/// What a master message that arrived through SharePlay Messenger says about the participant
/// the game master speaks from.
enum SharePlayMasterParticipantChange: Equatable, Sendable {
    case unchanged
    /// The first master message of this session.
    case learned
    /// The game master rejoined under another participant.
    case changed
}

@MainActor @Observable
final class PlayerControllerModel {
    private struct PendingMapUpdate: Sendable {
        let data: NetworkCodableDataType
        let counter: Int
    }

    private struct Presentation: Sendable {
        let counter: Int
        let module: NetworkModules
        let itemId: UUID
    }

    var gameUpdateType: NetworkModules = .none
    /// A photo the game master shows while a map is on screen: on the map, full screen or
    /// closed. See `PlayerController+MapPhoto.swift`.
    var mapPhoto = MapPhotoPresentationState()
    /// Makes the photo of a full-screen presentation the photo module's current item. One at a
    /// time: a newer presentation, a reset or the end of the game cancels it.
    @ObservationIgnored var mapPhotoMakeCurrentTask: Task<Void, Never>?
    /// The weather the game master shows on the 3D table. See `PlayerController+TableWeather.swift`.
    var tableWeather = TableWeatherState()
    var messageCounter: Int = 0
    private var outgoingMessageCounter: Int = 1
    private var lastMasterStateCounters: [UUID: Int] = [:]
    private var lastAudioListCounters: [UUID: Int] = [:]
    private var lastPhotoListCounters: [UUID: Int] = [:]
    private var lastPdfListCounters: [UUID: Int] = [:]
    private var lastSpaceListCounters: [UUID: Int] = [:]
    /// The newest master message that changed what this screen shows. A package of another
    /// item that arrives later with an older counter is stored but not shown.
    private var lastPresentation: Presentation?
    /// The SharePlay participant the game master's messages come from. The 3D table keeps it
    /// out of the player seats, and a master that rejoins under another participant gets this
    /// player's lists and Character again.
    private var sharePlayMasterParticipantId: UUID?
    private var sharePlayMasterParticipantLeft = false
    var lostMaster: Bool = true
    var hasSendPlayer = false
    /// How often the master answered `.failed` to this player's Character package, for which
    /// Character version, and when the next announcement may go out. A rejected package was
    /// announced again on every later master message, and exported and uploaded again each
    /// time, with no limit. See CODE_AUDIT_21 §5.5.
    private(set) var characterRejections = 0
    private var rejectedCharacterVersion: Int?
    private var characterRetryNotBefore: ContinuousClock.Instant?
    /// Rejections of one Character version after which it is no longer sent.
    static let maximumCharacterRejections = 3
    /// How often a rejected Character is looked at again for a changed version.
    static let rejectedCharacterProbeInterval: Duration = .seconds(60)
    var asGameMaster = false
    /// Counts the changes of the companion list. A send that ran while it changed has announced
    /// an old list, so it does not latch `hasSendPlayer` and runs again.
    /// See CODE_AUDIT_24 §5.5.
    private(set) var companionGeneration = 0
    func noteCompanionsChanged() {
        companionGeneration &+= 1
    }
    var sendCharacterTask: Task<Void, Never>?
    var sendCharacterTaskId: UUID?
    var proxyFocusTask: Task<Void, Never>?
    var proxyFocusTaskId: UUID?
    /// Pin photos of a map that were asked for on this connection, so every map state does
    /// not ask for them again.
    private var requestedPinPhotoIds: Set<UUID> = []
    // The live part of a map can arrive before the map itself: Messenger is faster than the
    // Journal. The newest content, state and battle round of each map wait here until the
    // map is there.
    private var pendingMapContentUpdates: [UUID: PendingMapUpdate] = [:]
    private var pendingMapStates: [UUID: PendingMapUpdate] = [:]
    private var pendingBattleRoundUpdates: [UUID: NetworkCodableDataType] = [:]
    private var lastMapContentCounters: [UUID: Int] = [:]
    private var lastMapStateCounters: [UUID: Int] = [:]
    /// When each map was last asked for, so a burst of states for a map that is still on its
    /// way asks once.
    private var lastMapRequests: [UUID: ContinuousClock.Instant] = [:]
    static let mapRequestInterval: Duration = .seconds(10)

    func increaseMessageCounter() {
        messageCounter += 1
    }

    func nextOutgoingMessageCounter() -> Int {
        defer { outgoingMessageCounter += 1 }
        return outgoingMessageCounter
    }

    // MARK: Master state

    func shouldApplyMasterState(from masterId: UUID, counter: Int) -> Bool {
        guard counter > 0 else { return true }
        guard counter > (lastMasterStateCounters[masterId] ?? 0) else { return false }
        lastMasterStateCounters[masterId] = counter
        return true
    }

    func resetMasterStateSequence() {
        lastMasterStateCounters.removeAll()
    }

    // MARK: SharePlay master participant

    func noteSharePlayMasterParticipant(id: UUID) -> SharePlayMasterParticipantChange {
        guard sharePlayMasterParticipantId != id else { return .unchanged }
        let isRejoin = sharePlayMasterParticipantId != nil || sharePlayMasterParticipantLeft
        sharePlayMasterParticipantId = id
        sharePlayMasterParticipantLeft = false
        return isRejoin ? .changed : .learned
    }

    @discardableResult
    func removeSharePlayMasterParticipant(id: UUID) -> Bool {
        guard sharePlayMasterParticipantId == id else { return false }
        sharePlayMasterParticipantId = nil
        sharePlayMasterParticipantLeft = true
        return true
    }

    func resetSharePlayMasterParticipant() {
        sharePlayMasterParticipantId = nil
        sharePlayMasterParticipantLeft = false
    }

    func isSharePlayMasterParticipant(id: UUID) -> Bool {
        sharePlayMasterParticipantId == id
    }

    // MARK: Availability lists

    func canApplyAudioList(from masterId: UUID, counter: Int) -> Bool {
        Self.isNewer(counter, than: lastAudioListCounters[masterId])
    }

    func recordAudioList(counter: Int, from masterId: UUID) {
        guard counter > 0 else { return }
        lastAudioListCounters[masterId] = counter
    }

    func canApplyPhotoList(from masterId: UUID, counter: Int) -> Bool {
        Self.isNewer(counter, than: lastPhotoListCounters[masterId])
    }

    func recordPhotoList(counter: Int, from masterId: UUID) {
        guard counter > 0 else { return }
        lastPhotoListCounters[masterId] = counter
    }

    func canApplyPdfList(from masterId: UUID, counter: Int) -> Bool {
        Self.isNewer(counter, than: lastPdfListCounters[masterId])
    }

    func recordPdfList(counter: Int, from masterId: UUID) {
        guard counter > 0 else { return }
        lastPdfListCounters[masterId] = counter
    }

    func canApplySpaceList(from masterId: UUID, counter: Int) -> Bool {
        Self.isNewer(counter, than: lastSpaceListCounters[masterId])
    }

    func recordSpaceList(counter: Int, from masterId: UUID) {
        guard counter > 0 else { return }
        lastSpaceListCounters[masterId] = counter
    }

    private static func isNewer(_ counter: Int, than last: Int?) -> Bool {
        guard counter >= 0 else { return false }
        guard counter > 0 else { return true }
        return counter > (last ?? 0)
    }

    // MARK: Presentation order

    /// Whether a master presentation is still what the game master wants on screen: it is
    /// the newest this player has seen, or it is for the item the newest one is for. The
    /// package of a map arrives after the state of that same map, which has a newer counter;
    /// only a later presentation of something else makes the package late.
    func isCurrentPresentation(counter: Int, module: NetworkModules, itemId: UUID) -> Bool {
        guard counter != 0, let last = lastPresentation else { return true }
        return counter >= last.counter || (last.module == module && last.itemId == itemId)
    }

    func markPresentation(counter: Int, module: NetworkModules, itemId: UUID) {
        guard counter >= (lastPresentation?.counter ?? 0) else { return }
        lastPresentation = Presentation(counter: counter, module: module, itemId: itemId)
    }

    // MARK: Map content and state

    func queueMapContentUpdate(_ data: NetworkCodableDataType, counter: Int) {
        guard shouldApplyMapContentUpdate(itemId: data.id, counter: counter) else { return }
        if let current = pendingMapContentUpdates[data.id], counter != 0, current.counter >= counter {
            return
        }
        pendingMapContentUpdates[data.id] = PendingMapUpdate(data: data, counter: counter)
    }

    func pendingMapContentUpdate(for itemId: UUID) -> (data: NetworkCodableDataType, counter: Int)? {
        guard let pending = pendingMapContentUpdates[itemId] else { return nil }
        return (pending.data, pending.counter)
    }

    func discardPendingMapContentUpdate(itemId: UUID) {
        pendingMapContentUpdates[itemId] = nil
    }

    /// Also asked before a map package is imported over a map this player already holds: a
    /// package that arrives after a newer content update would roll the map back.
    func shouldApplyMapContentUpdate(itemId: UUID, counter: Int) -> Bool {
        counter == 0 || counter > (lastMapContentCounters[itemId] ?? 0)
    }

    func markMapContentApplied(itemId: UUID, counter: Int) {
        if counter > 0 {
            lastMapContentCounters[itemId] = max(lastMapContentCounters[itemId] ?? 0, counter)
        }
        if let pending = pendingMapContentUpdates[itemId], pending.counter <= counter {
            pendingMapContentUpdates[itemId] = nil
        }
    }

    func queueMapState(_ data: NetworkCodableDataType, counter: Int) {
        guard shouldApplyMapState(itemId: data.id, counter: counter) else { return }
        if let current = pendingMapStates[data.id], counter != 0, current.counter >= counter {
            return
        }
        pendingMapStates[data.id] = PendingMapUpdate(data: data, counter: counter)
    }

    func pendingMapState(for itemId: UUID) -> (data: NetworkCodableDataType, counter: Int)? {
        guard let pending = pendingMapStates[itemId] else { return nil }
        return (pending.data, pending.counter)
    }

    func discardPendingMapState(itemId: UUID) {
        pendingMapStates[itemId] = nil
    }

    func shouldApplyMapState(itemId: UUID, counter: Int) -> Bool {
        counter == 0 || counter > (lastMapStateCounters[itemId] ?? 0)
    }

    func markMapStateApplied(itemId: UUID, counter: Int) {
        if counter > 0 {
            lastMapStateCounters[itemId] = max(lastMapStateCounters[itemId] ?? 0, counter)
        }
        pendingMapStates[itemId] = nil
    }

    /// The replay slot of a battle round update that arrived before its map. Always
    /// overwrites: a later update is at least as recent, and `applyRemoteState`'s own sequence
    /// check decides whether a replay is still worth applying. See CODE_AUDIT §5.2.
    func queueBattleRoundUpdate(_ data: NetworkCodableDataType) {
        pendingBattleRoundUpdates[data.id] = data
    }

    func pendingBattleRoundUpdate(for itemId: UUID) -> NetworkCodableDataType? {
        pendingBattleRoundUpdates[itemId]
    }

    func discardPendingBattleRoundUpdate(itemId: UUID) {
        pendingBattleRoundUpdates[itemId] = nil
    }

    /// Records a request for the map that answers a reveal, which is always sent.
    func noteMapRequest(itemId: UUID, now: ContinuousClock.Instant = .now) {
        lastMapRequests[itemId] = now
    }

    /// Whether a map state may ask for its map: not while a request of the last
    /// `mapRequestInterval` may still be answered.
    func mayRequestMap(itemId: UUID, now: ContinuousClock.Instant = .now) -> Bool {
        if let last = lastMapRequests[itemId], last.duration(to: now) < Self.mapRequestInterval {
            return false
        }
        lastMapRequests[itemId] = now
        return true
    }

    @discardableResult
    func insertRequestedPinPhotoId(_ id: UUID) -> Bool {
        requestedPinPhotoIds.insert(id).inserted
    }

    @discardableResult
    func removeRequestedPinPhotoId(_ id: UUID) -> Bool {
        requestedPinPhotoIds.remove(id) != nil
    }

    // MARK: Connection and Character

    func reset(lostMaster: Bool) {
        self.lostMaster = lostMaster
    }

    func reset(sendPlayer: Bool) {
        self.hasSendPlayer = sendPlayer
    }

    /// The screen the players share. Differs from `gameUpdateType` while the game master looks at
    /// something only this device opened, such as a hidden pin's photo: the map stays the shared
    /// screen. The late-joiner replay and an external display read this, never `gameUpdateType`.
    var sharedUpdateType: NetworkModules {
        mapPhoto.isLocal && mapPhoto.presentation != nil ? .map : gameUpdateType
    }

    func setGameUpdateType(_ type: NetworkModules) {
        gameUpdateType = type
    }

    /// Counts every time a weather is shown full screen. visionOS opens the weather window on
    /// each, also for the same weather again.
    private(set) var weatherWindowRequest = 0

    /// Shows the current weather full screen.
    func showWeather() {
        gameUpdateType = .weather
        weatherWindowRequest &+= 1
    }

    /// A live update of a map (its state or battle round) brings it to the front, unless a photo
    /// over that map is full screen: the photo's own buttons decide when the map returns. A
    /// reveal of a map is not a live update and closes the photo instead.
    func showMapForLiveUpdate(of mapId: UUID?) {
        if mapPhoto.mode == .fullScreen,
           let presentation = mapPhoto.presentation,
           presentation.mapId == mapId {
            return
        }
        gameUpdateType = .map
    }

    /// Reads both gate flags in one @MainActor property so a concurrent
    /// writer can't be observed between them. See CODE_AUDIT §3.1.
    var canSendCharacter: Bool {
        guard !hasSendPlayer, !lostMaster else { return false }
        if let characterRetryNotBefore, ContinuousClock.now < characterRetryNotBefore { return false }
        return true
    }

    /// The delay before the announcement after the `rejections`-th rejection: 5 s, then 20 s.
    static func characterRetryDelay(afterRejection rejections: Int) -> Duration {
        .seconds(5 * (1 << (2 * max(0, rejections - 1))))
    }

    /// Records the master's `.failed` answer for the Character package of `version`. Returns
    /// `true` when that was the rejection after which the Character is no longer sent, so the
    /// caller tells the player once. See CODE_AUDIT_21 §5.5.
    func recordCharacterRejection(version: Int, now: ContinuousClock.Instant = .now) -> Bool {
        if rejectedCharacterVersion != version {
            rejectedCharacterVersion = version
            characterRejections = 0
        }
        characterRejections += 1
        hasSendPlayer = false
        guard characterRejections < Self.maximumCharacterRejections else {
            characterRetryNotBefore = now + Self.rejectedCharacterProbeInterval
            return characterRejections == Self.maximumCharacterRejections
        }
        characterRetryNotBefore = now + Self.characterRetryDelay(afterRejection: characterRejections)
        return false
    }

    /// Whether the Character of `version` may be announced. A version the master rejected
    /// `maximumCharacterRejections` times stays unsent; it is looked at again after the probe
    /// interval, because an edited Character has a new version and gets new attempts.
    func mayAnnounceCharacter(version: Int, now: ContinuousClock.Instant = .now) -> Bool {
        guard characterRejections >= Self.maximumCharacterRejections else { return true }
        guard rejectedCharacterVersion == version else {
            resetCharacterRejections()
            return true
        }
        characterRetryNotBefore = now + Self.rejectedCharacterProbeInterval
        return false
    }

    /// A new connection, or an edited Character: earlier rejections no longer count.
    func resetCharacterRejections() {
        characterRejections = 0
        rejectedCharacterVersion = nil
        characterRetryNotBefore = nil
    }

    /// The read-then-conditionally-write needs to stay one @MainActor call so a
    /// concurrent reader never observes a state between the check and the clear.
    /// See CODE_AUDIT §3.1.
    func clearGameUpdateTypeIfPhoto() {
        if gameUpdateType == .photo {
            gameUpdateType = .none
        }
    }

    /// The batch of per-connection state a lost connection must clear atomically,
    /// pulled out of `PlayerController.resetForLostConnection` so the multi-property
    /// reset stays one `@MainActor` call from the controller instead of a
    /// `MainActor.run` closure. See CODE_AUDIT §3.1.
    func resetForLostConnection(preservingSharePlayRebind: Bool) {
        resetCharacterRejections()
        sendCharacterTask?.cancel()
        sendCharacterTask = nil
        sendCharacterTaskId = nil
        // See CODE_AUDIT_Game §3.10 — this task's delayed completion must not
        // overwrite `selectedCharacter` after the session it belongs to is gone.
        proxyFocusTask?.cancel()
        proxyFocusTask = nil
        proxyFocusTaskId = nil
        requestedPinPhotoIds = []
        resetMasterStateSequence()
        lastAudioListCounters.removeAll()
        lastPhotoListCounters.removeAll()
        lastPdfListCounters.removeAll()
        lastSpaceListCounters.removeAll()
        // A restarted game master counts from one again.
        lastPresentation = nil
        mapPhotoMakeCurrentTask?.cancel()
        mapPhotoMakeCurrentTask = nil
        mapPhoto.reset()
        tableWeather.reset()
        pendingMapContentUpdates.removeAll()
        pendingMapStates.removeAll()
        pendingBattleRoundUpdates.removeAll()
        lastMapContentCounters.removeAll()
        lastMapStateCounters.removeAll()
        lastMapRequests.removeAll()
        if !preservingSharePlayRebind {
            resetSharePlayMasterParticipant()
        }
    }
}
