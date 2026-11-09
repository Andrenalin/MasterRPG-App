// @copyright André Trettin

import AudioRPG
import AVFoundation
import CoreRPG
import Combine
import Foundation
import GroupActivities
import os.log
import SwiftUI

#if os(visionOS)
import TabletopKit
#endif

// See CODE_AUDIT §9.10 for the section boundaries below — added as
// `// MARK:` dividers rather than a physical file split, given the size of
// this file and the cross-references a full split would need to untangle.

// MARK: - Delegate protocol

@MainActor
protocol SharePlayControllerDelegate: AnyObject {
    func handleUpdate(_ model: GameNetworkModel, id: UUID) async -> Void
    func handleFileUpdate(_ model: GameNetworkModel) async -> Void
    func handleFileLoadFailure(_ model: GameNetworkModel) async -> Void
    /// Whether the Journal attachment of `model` is worth downloading. A device that already holds
    /// the file the attachment carries answers `false`: the Journal hands every participant every
    /// attachment, and the download of a large file is the slowest step of the game.
    func shouldLoadFile(_ model: GameNetworkModel) async -> Bool
    func sharePlayLostPlayer(id: UUID) async
    /// Called when the local SharePlay session is invalidated so the player
    /// controller can reset `hasSentPlayer` and mark the master as lost.
    func sharePlayLostConnection() async
    /// Called each time a session is fully configured and joined. On a player
    /// device this triggers `ready()` so audio availability and the selected
    /// character are re-announced after an automatic re-join.
    func sharePlaySessionConfigured() async
    /// Called on the game-master device when a remote participant becomes
    /// active in the joined session. Messenger has no history, so the current
    /// presentation must be replayed directly to this transport participant.
    func sharePlayJoinedPlayer(id: UUID) async
    /// The SharePlay participant this player device has pinned as the game master, if any of
    /// `participantIds` is it. Used to keep the master out of the table's player-seat ranking.
    func pinnedMasterParticipantId(among participantIds: [UUID]) async -> UUID?
}

extension SharePlayControllerDelegate {
    func pinnedMasterParticipantId(among participantIds: [UUID]) async -> UUID? { nil }
    func shouldLoadFile(_ model: GameNetworkModel) async -> Bool { true }
}

// MARK: - Session / activation / tracking support types

@MainActor
enum RPGSharePlay {
    static let store = RPGSharePlayController()
}

struct SharePlaySessionLifecycle: Sendable {
    private var sessionId: UUID?
    private var joinRequested = false
    private var configured = false

    mutating func prepare(sessionId: UUID) {
        self.sessionId = sessionId
        joinRequested = false
        configured = false
    }

    mutating func didRequestJoin(sessionId: UUID) {
        guard self.sessionId == sessionId else { return }
        joinRequested = true
    }

    mutating func didEnterJoinedState(sessionId: UUID) -> Bool {
        guard self.sessionId == sessionId, joinRequested, !configured else { return false }
        configured = true
        return true
    }

    func isCurrent(sessionId: UUID) -> Bool {
        self.sessionId == sessionId
    }

    mutating func reset() {
        sessionId = nil
        joinRequested = false
        configured = false
    }
}

struct SharePlaySessionOperationToken: Equatable, Sendable {
    let sessionId: UUID
    let generation: UInt64

    func canCommit(
        lifecycle: SharePlaySessionLifecycle,
        currentGeneration: UInt64,
        taskIsCancelled: Bool
    ) -> Bool {
        !taskIsCancelled &&
            lifecycle.isCurrent(sessionId: sessionId) &&
            generation == currentGeneration
    }
}

struct SharePlayActivationToken: Equatable, Sendable {
    let activityId: UUID
    let generation: UInt64
}

struct SharePlaySessionObserverToken: Equatable, Sendable {
    let generation: UInt64
}

struct SharePlaySessionObserverLifecycle: Sendable {
    private var generation: UInt64 = 0
    private(set) var acceptsSessions = false

    mutating func start(acceptsSessions: Bool) -> SharePlaySessionObserverToken {
        generation &+= 1
        self.acceptsSessions = acceptsSessions
        return SharePlaySessionObserverToken(generation: generation)
    }

    mutating func stop() {
        generation &+= 1
        acceptsSessions = false
    }

    func isCurrent(
        token: SharePlaySessionObserverToken,
        taskIsCancelled: Bool
    ) -> Bool {
        !taskIsCancelled && token.generation == generation
    }

    func canConfigure(
        token: SharePlaySessionObserverToken,
        taskIsCancelled: Bool
    ) -> Bool {
        acceptsSessions && isCurrent(token: token, taskIsCancelled: taskIsCancelled)
    }
}

enum SharePlayActivationSessionDisposition: Equatable, Sendable {
    case configure
    case leave
    case leaveAndStopCleanup
}

/// Binds local activation attempts to the exact RPGActivity later delivered by
/// sessions(). Cancellation cannot always abort the system activation await, so
/// an obsolete successful attempt is rejected when its tagged session arrives.
struct SharePlayActivationLifecycle: Sendable {
    private enum State: Equatable, Sendable {
        case active
        case obsolete
    }

    private var generation: UInt64 = 0
    private var currentToken: SharePlayActivationToken?
    private var states: [UUID: State] = [:]

    var hasObsoleteActivities: Bool {
        states.values.contains(.obsolete)
    }

    mutating func begin(activityId: UUID) -> SharePlayActivationToken {
        if let currentToken {
            states[currentToken.activityId] = .obsolete
        }
        generation &+= 1
        let token = SharePlayActivationToken(
            activityId: activityId,
            generation: generation
        )
        currentToken = token
        states[activityId] = .active
        return token
    }

    mutating func cancelCurrent() {
        if let currentToken {
            states[currentToken.activityId] = .obsolete
        }
        currentToken = nil
        generation &+= 1
    }

    func canCommit(
        token: SharePlayActivationToken,
        taskIsCancelled: Bool
    ) -> Bool {
        !taskIsCancelled &&
            token.generation == generation
    }

    mutating func didFinish(
        token: SharePlayActivationToken,
        activated: Bool
    ) {
        guard !activated else { return }
        states.removeValue(forKey: token.activityId)
        if currentToken == token {
            currentToken = nil
        }
    }

    mutating func dispositionForSession(
        activityId: UUID?,
        acceptsSessions: Bool
    ) -> SharePlayActivationSessionDisposition {
        var rejectedObsoleteActivity = false
        if let activityId, let state = states.removeValue(forKey: activityId) {
            if currentToken?.activityId == activityId {
                currentToken = nil
            }
            rejectedObsoleteActivity = state == .obsolete
        }

        if acceptsSessions {
            return rejectedObsoleteActivity ? .leave : .configure
        }
        return hasObsoleteActivities ? .leave : .leaveAndStopCleanup
    }
}

/// Revalidates a session-scoped loop on both sides of delegate suspension and
/// lets teardown await callbacks that were already admitted before reset.
/// Main-actor isolation makes admission plus active-count registration atomic
/// with respect to lifecycle reset.
@MainActor
final class SharePlaySessionCallbackCoordinator {
    private var activeCounts: [UUID: Int] = [:]
    private struct IdleWaiter {
        let id: UUID
        let continuation: CheckedContinuation<Bool, Never>
        let timeoutTask: Task<Void, Never>
    }

    /// Longest a session replacement waits for callbacks of the previous session.
    static let defaultIdleTimeout: Duration = .seconds(10)

    private var idleWaiters: [UUID: [IdleWaiter]] = [:]

    func perform(
        sessionId: UUID,
        shouldContinue: @MainActor () -> Bool,
        operation: @MainActor () async -> Void
    ) async -> Bool {
        guard !Task.isCancelled, shouldContinue() else { return false }
        activeCounts[sessionId, default: 0] += 1
        defer { finishCallback(sessionId: sessionId) }

        await operation()
        return !Task.isCancelled && shouldContinue()
    }

    /// Waits until no admitted callback of the session is running, but at most `timeout`.
    /// A hung delegate callback must not wedge the reconnection to a replacement session
    /// (CODE_AUDIT_Game_Shareplay §3.10). Returns `false` when it gave up waiting; the
    /// callback keeps running and is still revalidated by `perform` when it returns.
    @discardableResult
    func waitUntilIdle(sessionId: UUID, timeout: Duration = defaultIdleTimeout) async -> Bool {
        guard activeCounts[sessionId, default: 0] > 0 else { return true }
        let waiterId = UUID()
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                self?.expireWaiter(id: waiterId, sessionId: sessionId)
            }
            idleWaiters[sessionId, default: []].append(
                IdleWaiter(id: waiterId, continuation: continuation, timeoutTask: timeoutTask)
            )
        }
    }

    private func expireWaiter(id: UUID, sessionId: UUID) {
        guard var waiters = idleWaiters[sessionId],
              let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = waiters.remove(at: index)
        idleWaiters[sessionId] = waiters.isEmpty ? nil : waiters
        Logger.networking.error("SharePlay: gave up waiting for callbacks of the previous session")
        waiter.continuation.resume(returning: false)
    }

    private func finishCallback(sessionId: UUID) {
        let remainingCount = activeCounts[sessionId, default: 0] - 1
        guard remainingCount <= 0 else {
            activeCounts[sessionId] = remainingCount
            return
        }

        activeCounts.removeValue(forKey: sessionId)
        for waiter in idleWaiters.removeValue(forKey: sessionId) ?? [] {
            waiter.timeoutTask.cancel()
            waiter.continuation.resume(returning: true)
        }
    }
}

/// Keeps teardown callbacks alive independently of the session task being
/// cancelled, and gives a replacement configuration one operation to await.
/// The token prevents an older waiter from clearing a newer teardown.
@MainActor
final class SharePlaySessionTeardownCoordinator {
    struct Operation {
        fileprivate let token: UUID
        fileprivate let task: Task<Void, Never>
    }

    private struct PendingTeardown {
        let token: UUID
        let task: Task<Void, Never>
    }

    private var pendingTeardown: PendingTeardown?

    func waitForPendingTeardown() async {
        while let pendingTeardown {
            await pendingTeardown.task.value
            clearPendingTeardown(matching: pendingTeardown.token)
        }
    }

    /// Registration is synchronous so a caller can publish the pending token
    /// before reset opens the main-actor reentrancy window.
    func start(
        _ operation: @escaping @MainActor @Sendable () async -> Void
    ) -> Operation {
        let precedingTask = pendingTeardown?.task
        let token = UUID()
        let task = Task { @MainActor in
            if let precedingTask {
                await precedingTask.value
            }
            await operation()
        }
        pendingTeardown = PendingTeardown(token: token, task: task)
        return Operation(token: token, task: task)
    }

    func waitForCompletion(of operation: Operation) async {
        await operation.task.value
        clearPendingTeardown(matching: operation.token)
    }

    private func clearPendingTeardown(matching token: UUID) {
        guard pendingTeardown?.token == token else { return }
        pendingTeardown = nil
    }
}

enum SharePlaySessionTeardownEvent: Equatable, Sendable {
    case lostParticipant(UUID)
    case lostConnection
}

enum SharePlayConnectionState: Equatable, Sendable {
    case inactive
    case waiting
    case joined
    case disconnected
}

/// Tracks transport participants independently of in-game player identities.
///
/// `Participant.id` is the address used by `GroupSessionMessenger`; it is not
/// the UUID a player announces later in `GameSenderModel`. Keeping those two
/// identities separate lets the master physically target an initial replay
/// before the player's normal join handshake has completed.
struct SharePlayParticipantTracker: Sendable {
    struct Change: Equatable, Sendable {
        let added: Set<UUID>
        let removed: Set<UUID>
    }

    private var activeRemoteParticipantIds: Set<UUID> = []
    private var replayedParticipantIds: Set<UUID> = []

    mutating func sessionDidJoin(
        activeParticipantIds: Set<UUID>,
        localParticipantId: UUID
    ) -> Set<UUID> {
        let remoteParticipantIds = activeParticipantIds.subtracting([localParticipantId])
        activeRemoteParticipantIds = remoteParticipantIds
        replayedParticipantIds.formIntersection(remoteParticipantIds)

        let added = remoteParticipantIds.subtracting(replayedParticipantIds)
        replayedParticipantIds.formUnion(added)
        return added
    }

    mutating func participantsChanged(
        activeParticipantIds: Set<UUID>,
        localParticipantId: UUID,
        sessionIsJoined: Bool
    ) -> Change {
        let remoteParticipantIds = activeParticipantIds.subtracting([localParticipantId])
        let removed = activeRemoteParticipantIds.subtracting(remoteParticipantIds)
        activeRemoteParticipantIds = remoteParticipantIds
        replayedParticipantIds.subtract(removed)

        guard sessionIsJoined else {
            return Change(added: [], removed: removed)
        }

        let added = remoteParticipantIds.subtracting(replayedParticipantIds)
        replayedParticipantIds.formUnion(added)
        return Change(added: added, removed: removed)
    }

    /// Captures every old transport participant before a session reset clears
    /// the tracker. The connection event is deliberately last so participant-
    /// scoped availability is removed before the player performs its complete
    /// lost-master reset.
    mutating func drainSessionTeardownEvents() -> [SharePlaySessionTeardownEvent] {
        let participantEvents = activeRemoteParticipantIds
            .sorted(by: { $0.uuidString < $1.uuidString })
            .map(SharePlaySessionTeardownEvent.lostParticipant)
        reset()
        return participantEvents + [.lostConnection]
    }

    mutating func reset() {
        activeRemoteParticipantIds = []
        replayedParticipantIds = []
    }
}

enum SharePlayPackageDeliveryError: LocalizedError, SharePlayTerminalPackageError {
    case participantNotActive(UUID)

    var errorDescription: String? {
        switch self {
        case .participantNotActive(let id):
            "SharePlay participant \(id) is no longer active"
        }
    }
}

enum SharePlayChunkedDeliveryOutcome: Equatable, Sendable {
    case succeeded
    case retryableFailure
    case terminalFailure
    case cancelled
}

// MARK: - Controller state & setup

@MainActor @Observable
final class RPGSharePlayController {
    struct PendingSendOperation {
        let id: UUID
        let byteCount: Int
        let operation: @MainActor () async -> Void
    }

    var groupSession: GroupSession<RPGActivity>?
    /// Orders the current session's `join()` and `leave()`. Leave the session through
    /// `leaveGroupSession()`, never `groupSession?.leave()`.
    var sessionCommands: GroupSessionCommandQueue?
    var isActive: Bool = false
    var connectionState: SharePlayConnectionState = .inactive
    var canActivateSharePlay: Bool = false
    /// What a running master game offers SharePlay with, kept while the game runs so a call
    /// that starts (or restarts) after the game activates it. `nil` when no master game runs.
    /// See CODE_AUDIT_Game_Shareplay §5.20.
    var pendingActivation: PendingActivation?
    struct PendingActivation {
        let name: String?
        let image: AKImage?
    }
    var stateText: String = "Not Active"

    var gameModel: GameRootModel?
    var packageSender: SharePlaySingleQueuePackageSender?
    var packageReceiver = SharePlayPackageReceiver()
    var inboundByteBudget = SharePlayInboundByteBudget()
    /// The bytes of Journal attachments one participant has had loaded per minute. Kept apart
    /// from `inboundByteBudget`, which counts Messenger packages.
    /// See CODE_AUDIT_Game_Shareplay §6.2.
    var journalLoadBudget = SharePlayInboundByteBudget()

    // Kept alive through session resets so the player can re-join automatically
    // when SharePlay becomes available again for a running game. Only cancelled
    // by stopJoin() when the game itself ends.
    var joinTask: Task<Void, Never>?
    var sessionObserverLifecycle = SharePlaySessionObserverLifecycle()
    var activationTask: Task<Void, Never>?
    var activationLifecycle = SharePlayActivationLifecycle()

    #if os(visionOS)
    var systemCoordinator: SystemCoordinator?
    /// Identifies the `TabletopGame` instance `deferCoordinateAndAssignSeats`
    /// has already coordinated, so the two independent triggers that can both
    /// reach it — `setup(tabletopGame:gameTableModel:)` (table view opens
    /// after the session already exists) and `configureGroupSession` (the
    /// session starts while the table view is already open) — coordinate the
    /// same instance at most once, no matter which fires first or how many
    /// times either fires. Each defers its own call into a `Task { @MainActor
    /// }` (blocking-main-thread reasons — see `deferCoordinateAndAssignSeats`'s
    /// own doc), and a `Task` whose body never checks `Task.isCancelled` still
    /// runs to completion even after `trackSessionTask` cancels it. Without
    /// this guard, both triggers landing on the same instance called
    /// `coordinateWithSession` twice and submitted a duplicate `claimSeat`
    /// each, corrupting TabletopKit's shared-simulation role/template
    /// negotiation and reliably reproducing "Could not find static equipment
    /// with identifier: ..." moments later — reproduced on-device 2026-08-22
    /// pairing a Release and a Debug build (their differing startup speed is
    /// exactly what exposes the ordering).
    /// Identifies which session a `tabletopGame` instance was actually
    /// coordinated with, not merely whether it was coordinated at all. A
    /// deferred task's body never checks `Task.isCancelled` (see
    /// `deferCoordinateAndAssignSeats`'s doc), so one scheduled for an
    /// already-invalidated session can still run after `reset()` cleared this
    /// property back to `nil` and land *before* the replacement session
    /// schedules its own deferred task — coordinating `tabletopGame` with the
    /// stale, dead session and marking that tabletopGame instance "already
    /// coordinated" before the real, current session ever gets a turn. Keying
    /// by (tabletopGame identity, session id) together — and re-validating
    /// session currency immediately before the call, not just at scheduling
    /// time — closes that gap. See CODE_AUDIT_Reconnect §3.4.
    struct CoordinatedSession: Equatable {
        let tabletopGameId: ObjectIdentifier
        let sessionId: UUID
    }
    var coordinatedTabletopGame: CoordinatedSession?
    #endif

    let groupStateObserver = GroupStateObserver()

    var messenger: GroupSessionMessenger?
    var sessionLifecycle = SharePlaySessionLifecycle()
    var participantTracker = SharePlayParticipantTracker()
    var journalLedger = SharePlayJournalLedger()
    let sessionCallbackCoordinator = SharePlaySessionCallbackCoordinator()
    let sessionTeardownCoordinator = SharePlaySessionTeardownCoordinator()
    // Session-scoped state/participant/message/journal loops, cancelled by reset().
    var tasks: [UUID: Task<Void, Never>] = [:]
    // Journal snapshots are full sets, so only the newest one matters. The stream consumer
    // records it here and a single drain task processes it; a slow or hung attachment load can
    // no longer keep later publications from even being looked at.
    var pendingJournalSnapshot: GroupSessionJournal.Attachments.Element?
    /// Metadata of each attachment already seen, so a snapshot that lists it again does not load
    /// it again. Pruned to the attachments of the newest snapshot. See CODE_AUDIT_23 §6.5.
    var journalMetadataCache: [UUID: GameNetworkModel] = [:]
    var currentJournalAttachmentIds: Set<UUID> = []
    var journalDrainTask: Task<Void, Never>?
    /// The Journal load that runs for each item, so a newer publication of the item waits for the
    /// older one. Loads of different items run side by side.
    var journalLoadTasks: [UUID: (token: UUID, task: Task<Void, Never>)] = [:]
    /// Whether the first snapshot with something to load (a late joiner's) was handled: it loads
    /// in message order, every later one concurrently.
    var journalJoinBatchHandled = false
    // Normal Messenger sends are admitted before encoding, then processed in
    // invocation order. This prevents a burst from spawning unbounded parallel
    // Base64 encodes before the package sender can apply its own bounds.
    var pendingSendOperations: [PendingSendOperation] = []
    var activeSendOperation: PendingSendOperation?
    var sendOperationByteCount = 0
    var sendOperationTask: Task<Void, Never>?
    var sendOperationGeneration: UInt64 = 0
    var deferredDeliveryQueue = SharePlayDeferredDeliveryQueue()
    var deferredPromotionTask: Task<Void, Never>?
    /// The newest state update sent per entity; see `SharePlayStateSupersession`.
    var stateSupersession = SharePlayStateSupersession()
    // Publications for one module are serialized, but cleanup of the previous
    // attachment never blocks publication of the next map/photo/PDF/space.
    let journalPublicationQueue = SharePlayJournalPublicationQueue<GroupSessionJournal.Attachment>()
    /// Keyed by the same slot as the publication queue: an audio playlist and its first track are
    /// published at the same time and must not block each other. See CODE_AUDIT_Game_Shareplay §5.10.
    let journalAddLimiter = SharePlayJournalAddLimiter<SharePlayJournalSlot, GroupSessionJournal.Attachment>()
    var journal: GroupSessionJournal?

    static let journalAddTimeout: Duration = .seconds(10)
    /// One send and three retries. A single retry after one second dropped the message while
    /// a large transfer still held the send queue. See CODE_AUDIT_21 §5.6.
    static let maxChunkedDeliveryAttempts = 4
    static let chunkedRetryDelay: Duration = .seconds(1)

    /// The wait before retry number `attempt` (1, 2, 3): 1 s, 2 s, 4 s.
    static func chunkedRetryDelay(forAttempt attempt: Int) -> Duration {
        chunkedRetryDelay * (1 << max(0, min(attempt, maxChunkedDeliveryAttempts) - 1))
    }

    // Lifetime observers — survive session resets; re-created if setup() runs again.
    var eligibilityTask: Task<Void, Never>?

    weak var delegate: SharePlayControllerDelegate?
    weak var playBack: AVPlaybackCoordinator?
    weak var audioCoordinator: AudioListenerCoordinator?

    /// The player behind each session participant: the name their game messages carry, and
    /// whether they play on Vision Pro and so sit at the 3D table. Learned from the
    /// authenticated player messages a participant sends itself; the table uses it to tell which
    /// player sits at which seat. See `bindPlayer(named:hasTable:participantId:)`.
    @ObservationIgnored
    var participantPlayers: [UUID: ParticipantPlayer] = [:]

    struct ParticipantPlayer: Equatable {
        let name: String
        let hasTable: Bool
    }

#if os(visionOS)
    weak var tabletopGame: TabletopGame?
    /// The table whose seats follow this session, so a late master pin can re-seat it.
    /// See CODE_AUDIT_18 §5.11.
    weak var seatingGameTableModel: GameTableModel?
#endif

    init() {
        Logger.sharePlay.debug("SharePlay: init")
    }

    #if os(visionOS)
    /// Lifetime observer of the presentation mode; like `eligibilityTask`, it survives a
    /// session `reset()`. See CODE_AUDIT_18 §3.21.
    var modeChangeTask: Task<Void, Never>?
    #endif

    isolated deinit {
        // `isolated deinit` (matching `ListenerManager`/`BrowserManager`/`GameTableModel` in
        // this module) runs on the actor, so it can self-clean instead of relying on every
        // caller to remember `reset()` first. `reset()` deliberately leaves `eligibilityTask`/
        // `joinTask`/`modeChangeTask` running — they're lifetime observers meant to survive a
        // session reset (see their declarations above) — so cancel those separately here to
        // stop every task this instance owns, not just the session-scoped ones. See CODE_AUDIT §3.3.
        reset()
        eligibilityTask?.cancel()
        joinTask?.cancel()
        #if os(visionOS)
        modeChangeTask?.cancel()
        #endif
        Logger.sharePlay.debug("SharePlay: deinit")
    }

    /// A master game that started while the device could not offer SharePlay activates it when it
    /// becomes eligible (the game master starts a FaceTime call after the game).
    nonisolated static func shouldActivateOnEligibilityChange(
        wasEligible: Bool,
        isEligible: Bool,
        hasPendingActivation: Bool,
        hasSession: Bool,
        isActivating: Bool
    ) -> Bool {
        isEligible && !wasEligible && hasPendingActivation && !hasSession && !isActivating
    }

    func setup(gameModel: GameRootModel) {
        Logger.sharePlay.debug("SharePlay: setup")
        self.gameModel = gameModel

        eligibilityTask?.cancel()
        eligibilityTask = Task { [weak self] in
            guard let observer = self?.groupStateObserver else { return }
            for await value in observer.$isEligibleForGroupSession.values {
                guard let self else { return }
                let wasEligible = self.canActivateSharePlay
                self.canActivateSharePlay = value
                if Self.shouldActivateOnEligibilityChange(
                    wasEligible: wasEligible,
                    isEligible: value,
                    hasPendingActivation: self.pendingActivation != nil,
                    hasSession: self.groupSession != nil,
                    isActivating: self.activationTask != nil
                ), let pending = self.pendingActivation {
                    Logger.sharePlay.debug("SharePlay: eligible during a running game, activating")
                    if self.joinTask == nil { self.joinGame() }
                    self.startSharing(with: pending.name, image: pending.image)
                }
            }
        }

        #if os(visionOS)
        // Observe presentation mode changes and apply configuration.
        // `GameShareStateModel.mode` is `@Observable`, so an `Observations` loop is
        // enough (no Combine subject). See CODE_AUDIT §4.2 and CODE_AUDIT_18 §3.21.
        observeShareStateMode()
        #endif
    }

    #if os(visionOS)
    func observeShareStateMode() {
        guard let gameModel else { return }
        modeChangeTask?.cancel()
        modeChangeTask = Task { @MainActor [weak self] in
            var isInitialValue = true
            for await mode in Observations({ gameModel.shareState.mode }) {
                // `Observations` also yields the current value; only changes apply.
                if isInitialValue {
                    isInitialValue = false
                    continue
                }
                guard let self, !Task.isCancelled else { return }
                Logger.sharePlay.debug("Presentation mode changed to: \(mode.rawValue, privacy: .public)")
                // `applyShareState()` itself returns early once `reset()` cleared the coordinator.
                self.applyShareState()
            }
        }
    }
    #endif

    func setup(audioCoordinator: AudioListenerCoordinator?) {
        self.audioCoordinator = audioCoordinator
        self.playBack = audioCoordinator?.playbackCoordinator
        guard let groupSession else { return }
        playBack?.coordinateWithSession(groupSession)
    }

    #if os(visionOS)
    func setup(tabletopGame: TabletopGame, gameTableModel: GameTableModel? = nil) {
        // A new instance never inherits the coordination of an earlier one: the guard compares
        // `ObjectIdentifier`s, and a game allocated at the address of a released one would
        // otherwise match and never be coordinated. See CODE_AUDIT_Game_Shareplay §5.15.
        if self.tabletopGame !== tabletopGame {
            coordinatedTabletopGame = nil
        }
        self.tabletopGame = tabletopGame
        if let groupSession {
            deferCoordinateAndAssignSeats(
                tabletopGame: tabletopGame,
                groupSession: groupSession,
                gameTableModel: gameTableModel
            )
        } else if let gameTableModel {
            setupLocalSeatAssignment(gameTableModel: gameTableModel)
        }
    }

    /// Coordinates `tabletopGame` with `groupSession` and assigns seats — but
    /// see `coordinatedTabletopGame`'s own doc for why doing that at most
    /// once per `tabletopGame` instance needs an explicit guard, not just
    /// `trackSessionTask`'s cancel-and-replace.
    ///
    /// Deferred into its own main-actor turn (never called inline) because
    /// `coordinateWithSession` is a synchronous, @MainActor-required
    /// TabletopKit call that can block the main thread while the audio
    /// session is active (its internal AVAudioSession route/category
    /// reconfiguration — SessionCore::setCategory). Apple's own TabletopKit
    /// sample defers this exact call inside `Task { @MainActor in }` for the
    /// same reason.
    ///
    /// `setupSeatAssignment` is chained *inside* this same deferred task,
    /// after `coordinateWithSession` returns, rather than fired separately
    /// and synchronously by the caller (as it used to be, via
    /// `GameTableModel.setupSeating`). `claimSeat`/`claimAnySeat` are
    /// themselves TabletopKit-synchronized actions — submitting one before
    /// this game's network coordinator is attached to the group session left
    /// a joining player's seat claim unsynced against the master's
    /// already-running session. TabletopKit's own internal reconciliation
    /// could then no longer resolve an in-flight synced update against the
    /// mismatched local state, crashing every joining player with "Could not
    /// find static equipment with identifier: ...". The master never hits
    /// this because it originates the session instead of reconciling into
    /// one; local (non-SharePlay) play never hits it because
    /// `coordinateWithSession` is never called at all there — see
    /// `GameTableModel.setupSeating`'s own doc.
    func deferCoordinateAndAssignSeats(
        tabletopGame: TabletopGame,
        groupSession: GroupSession<RPGActivity>,
        gameTableModel: GameTableModel?
    ) {
        let task = Task { @MainActor [weak self, weak tabletopGame, weak gameTableModel] in
            guard let self, let tabletopGame, self.tabletopGame === tabletopGame else { return }
            // Re-validate session currency immediately before coordinating,
            // not just at scheduling time. This task's body never checks
            // `Task.isCancelled` (see this function's own doc), so one
            // scheduled for an already-superseded session can still run —
            // without this guard it would bind `tabletopGame` to a stale,
            // dead `GroupSession` and mark that instance "coordinated" ahead
            // of the real, current session's own deferred task, permanently
            // starving it. See CODE_AUDIT_Reconnect §3.4.
            guard self.sessionLoopIsCurrent(sessionId: groupSession.id) else {
                Logger.sharePlay.debug("Skipped TabletopKit coordination for a superseded session \(groupSession.id, privacy: .public)")
                return
            }
            let identifier = CoordinatedSession(tabletopGameId: ObjectIdentifier(tabletopGame), sessionId: groupSession.id)
            guard self.coordinatedTabletopGame != identifier else { return }
            self.coordinatedTabletopGame = identifier
            tabletopGame.coordinateWithSession(groupSession)
            if let gameTableModel {
                await self.setupSeatAssignment(gameTableModel: gameTableModel)
            } else {
                Logger.sharePlay.debug("GameTableModel not available at session configure time — seats assigned later")
            }
        }
        trackSessionTask(task, key: Self.coordinateSessionTaskKey)
    }
    #endif
}

#if os(visionOS)
extension RPGSharePlayController {
    static let coordinateSessionTaskKey = UUID()
}
#endif

extension RPGSharePlayController {
    func printState() -> String {
        guard let groupSession else {
            return "Not Active"
        }
        return "\(groupSession.state)"
    }
}
