// @copyright André Trettin

import CoreRPG
import Foundation

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
    private var outgoingMessageCounter: Int = 1
    private var lastMasterStateCounters: [UUID: Int] = [:]
    /// The order of the availability lists of the game master. See `ListSequenceTracker`.
    private var listSequence = ListSequenceTracker()
    /// The newest master message that changed what this screen shows. A package of another
    /// item that arrives later with an older counter is stored but not shown.
    private var lastPresentation: Presentation?
    /// The SharePlay participant the game master's messages come from. The 3D table keeps it
    /// out of the player seats, and a master that rejoins under another participant gets this
    /// player's lists and Character again.
    private var sharePlayMasterParticipantId: UUID?
    private var sharePlayMasterParticipantLeft = false
    var lostMaster: Bool = true
    var hasSentPlayer = false
    /// How often the master rejected this player's Character package, and when the next
    /// announcement may go out. See `CharacterRejectionPolicy`.
    private var characterRejectionPolicy = CharacterRejectionPolicy()
#if DEBUG
    /// A test affordance.
    var characterRejections: Int { characterRejectionPolicy.rejections }
#endif
    var asGameMaster = false
    /// Counts the changes of the companion list. A send that ran while it changed has announced
    /// an old list, so it does not latch `hasSentPlayer` and runs again.
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
    /// The live part of a map that arrived before the map itself, and the order of the map
    /// updates already applied. See `PendingMapUpdateQueue`.
    var mapUpdates = PendingMapUpdateQueue()

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

    /// Forgets how far the game master's counters had come: its master-state sequence, the
    /// availability lists and the presentation order. A restarted game master counts from one
    /// again, and until its counters pass the old high-water marks every config, roster and
    /// presentation of it would count as stale. Shared by the lost connection and by a master
    /// that comes back under another SharePlay participant. See
    /// CODE_AUDIT_Game_Shareplay §5.3.
    func resetMasterSequences() {
        resetMasterStateSequence()
        listSequence.reset()
        lastPresentation = nil
        forwardedProxyKeys.removeAll()
        forwardedProxyKeyOrder.removeAll()
    }

    // MARK: Proxy forwarding

    private var forwardedProxyKeys: Set<GameMessageKey> = []
    private var forwardedProxyKeyOrder: [GameMessageKey] = []
    private static let maximumForwardedProxyKeys = 512

    /// Whether the message under `key` is forwarded to the proxy clients now: once per key,
    /// however often it is redelivered or rejected only by this device's policy.
    /// See CODE_AUDIT_Game_Shareplay §5.22.
    func claimProxyForward(_ key: GameMessageKey) -> Bool {
        guard forwardedProxyKeys.insert(key).inserted else { return false }
        forwardedProxyKeyOrder.append(key)
        if forwardedProxyKeyOrder.count > Self.maximumForwardedProxyKeys {
            forwardedProxyKeys.remove(forwardedProxyKeyOrder.removeFirst())
        }
        return true
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

    func canApplyList(_ module: NetworkModules, from masterId: UUID, counter: Int) -> Bool {
        listSequence.canApply(module, from: masterId, counter: counter)
    }

    func recordList(_ module: NetworkModules, counter: Int, from masterId: UUID) {
        listSequence.record(module, counter: counter, from: masterId)
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
        self.hasSentPlayer = sendPlayer
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
        guard !hasSentPlayer, !lostMaster else { return false }
        if characterRejectionPolicy.isDelayed() { return false }
        return true
    }

    /// Records the master's `.failed` answer for the Character package of `version`. Returns
    /// `true` when that was the rejection after which the Character is no longer sent, so the
    /// caller tells the player once. See CODE_AUDIT_21 §5.5.
    func recordCharacterRejection(version: Int, now: ContinuousClock.Instant = .now) -> Bool {
        hasSentPlayer = false
        return characterRejectionPolicy.record(version: version, now: now)
    }

    /// Whether the Character of `version` may be announced. See `CharacterRejectionPolicy`.
    func mayAnnounceCharacter(version: Int, now: ContinuousClock.Instant = .now) -> Bool {
        characterRejectionPolicy.mayAnnounce(version: version, now: now)
    }

    /// A new connection, or an edited Character: earlier rejections no longer count.
    func resetCharacterRejections() {
        characterRejectionPolicy.reset()
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
        resetMasterSequences()
        mapPhotoMakeCurrentTask?.cancel()
        mapPhotoMakeCurrentTask = nil
        mapPhoto.reset()
        tableWeather.reset()
        mapUpdates.reset()
        if !preservingSharePlayRebind {
            resetSharePlayMasterParticipant()
        }
    }
}
