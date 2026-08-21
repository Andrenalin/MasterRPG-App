// @copyright André Trettin

import AudioRPG
import AVFoundation
import CoreRPG
import Combine
import Foundation
@preconcurrency import GroupActivities
import os.log
import SwiftUI

#if os(visionOS)
import TabletopKit
#endif

@MainActor
protocol SharePlayControllerDelegate: AnyObject {
    func handleUpdate(_ model: GameNetworkModel, id: UUID) async -> Void
    func handleFileUpdate(_ model: GameNetworkModel) async -> Void
    func handleFileLoadFailure(_ model: GameNetworkModel) async -> Void
    func sharePlayLostPlayer(id: UUID) async
    /// Called when the local SharePlay session is invalidated so the player
    /// controller can reset `hasSendPlayer` and mark the master as lost.
    func sharePlayLostConnection() async
    /// Called each time a session is fully configured and joined. On a player
    /// device this triggers `ready()` so audio availability and the selected
    /// character are re-announced after an automatic re-join.
    func sharePlaySessionConfigured() async
    /// Called on the game-master device when a remote participant becomes
    /// active in the joined session. Messenger has no history, so the current
    /// presentation must be replayed directly to this transport participant.
    func sharePlayJoinedPlayer(id: UUID) async
}

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
    private var idleWaiters: [UUID: [CheckedContinuation<Void, Never>]] = [:]

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

    func waitUntilIdle(sessionId: UUID) async {
        guard activeCounts[sessionId, default: 0] > 0 else { return }
        await withCheckedContinuation { continuation in
            idleWaiters[sessionId, default: []].append(continuation)
        }
    }

    private func finishCallback(sessionId: UUID) {
        let remainingCount = activeCounts[sessionId, default: 0] - 1
        guard remainingCount <= 0 else {
            activeCounts[sessionId] = remainingCount
            return
        }

        activeCounts.removeValue(forKey: sessionId)
        idleWaiters.removeValue(forKey: sessionId)?.forEach { $0.resume() }
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

private enum SharePlayPackageDeliveryError: LocalizedError {
    case participantNotActive(UUID)

    var errorDescription: String? {
        switch self {
        case .participantNotActive(let id):
            "SharePlay participant \(id) is no longer active"
        }
    }
}

private enum SharePlayChunkedDeliveryOutcome: Equatable, Sendable {
    case succeeded
    case retryableFailure
    case terminalFailure
    case cancelled
}

enum SharePlayJournalReuseDisposition: Equatable, Sendable {
    case reuseExistingAttachment
    case publishFreshAttachment

    init(metadataAdmissionSucceeded: Bool) {
        self = metadataAdmissionSucceeded ? .reuseExistingAttachment : .publishFreshAttachment
    }
}

struct SharePlayJournalTracker: Sendable {
    struct Publication: Equatable, Sendable {
        let attachmentId: UUID
        let itemId: UUID
        let version: Int
    }

    private var processedAttachmentIds: Set<UUID> = []
    private var publications: [NetworkModules: Publication] = [:]
    /// Developer metadata for currently observed attachments. Remote metadata
    /// enters the replay set only after the normal participant-attributed
    /// admission path authenticates it; otherwise the master could accidentally
    /// launder a forged anonymous attachment when a new player joins.
    private var observedMetadataByAttachmentId: [UUID: GameNetworkModel] = [:]
    private var authenticatedMetadataByAttachmentId: [UUID: GameNetworkModel] = [:]
    private var attachmentArrivalEpochs: [UUID: UInt64] = [:]
    private var nextArrivalEpoch: UInt64 = 0

    mutating func reconcile(attachmentIds: Set<UUID>) {
        processedAttachmentIds.formIntersection(attachmentIds)
        publications = publications.filter { attachmentIds.contains($0.value.attachmentId) }
        observedMetadataByAttachmentId = observedMetadataByAttachmentId.filter { attachmentIds.contains($0.key) }
        authenticatedMetadataByAttachmentId = authenticatedMetadataByAttachmentId.filter { attachmentIds.contains($0.key) }
        attachmentArrivalEpochs = attachmentArrivalEpochs.filter { attachmentIds.contains($0.key) }

        let newlyObservedAttachmentIds = attachmentIds.subtracting(Set(attachmentArrivalEpochs.keys))
        guard !newlyObservedAttachmentIds.isEmpty else { return }
        nextArrivalEpoch &+= 1
        for attachmentId in newlyObservedAttachmentIds {
            attachmentArrivalEpochs[attachmentId] = nextArrivalEpoch
        }
    }

    func arrivalEpoch(for attachmentId: UUID) -> UInt64 {
        attachmentArrivalEpochs[attachmentId] ?? 0
    }

    func shouldPublish(module: NetworkModules, itemId: UUID, version: Int) -> Bool {
        guard let publication = publications[module] else { return true }
        return publication.itemId != itemId || publication.version != version
    }

    /// A targeted Audio or Weather repair must replace the current journal
    /// attachment even when it carries the same item and asset version. The
    /// recipient may have missed or failed to load that attachment; reusing it
    /// would deliver no new journal event to that player.
    func shouldPublish(model: GameNetworkModel) -> Bool {
        if model.sender.isMaster,
           model.targetId != nil,
           model.data.data != nil,
           (model.data.type == .audio || model.data.type == .weather) {
            return true
        }
        return shouldPublish(
            module: model.data.type,
            itemId: model.data.id,
            version: model.data.effectiveAssetVersion
        )
    }

    mutating func didPublish(
        module: NetworkModules,
        itemId: UUID,
        version: Int,
        attachmentId: UUID,
        metadata: GameNetworkModel? = nil
    ) {
        publications[module] = Publication(attachmentId: attachmentId, itemId: itemId, version: version)
        processedAttachmentIds.insert(attachmentId)
        if let metadata {
            observedMetadataByAttachmentId[attachmentId] = metadata
            authenticatedMetadataByAttachmentId[attachmentId] = metadata
        }
    }

    mutating func didObserve(attachmentId: UUID, metadata: GameNetworkModel) {
        observedMetadataByAttachmentId[attachmentId] = metadata
        if publications.values.contains(where: { $0.attachmentId == attachmentId }) {
            authenticatedMetadataByAttachmentId[attachmentId] = metadata
        }
    }

    mutating func didAuthenticate(_ model: GameNetworkModel) {
        for (attachmentId, metadata) in observedMetadataByAttachmentId
        where metadata.hasSameJournalFingerprint(as: model) {
            authenticatedMetadataByAttachmentId[attachmentId] = metadata
        }
    }

    func currentJournalMetadata() -> [(attachmentId: UUID, metadata: GameNetworkModel)] {
        authenticatedMetadataByAttachmentId.map {
            (attachmentId: $0.key, metadata: $0.value)
        }
    }

    mutating func didRemove(attachmentId: UUID) {
        processedAttachmentIds.remove(attachmentId)
        publications = publications.filter { $0.value.attachmentId != attachmentId }
        observedMetadataByAttachmentId[attachmentId] = nil
        authenticatedMetadataByAttachmentId[attachmentId] = nil
        attachmentArrivalEpochs[attachmentId] = nil
    }

    mutating func shouldProcess(attachmentId: UUID) -> Bool {
        processedAttachmentIds.insert(attachmentId).inserted
    }

    mutating func retryProcessing(attachmentId: UUID) {
        processedAttachmentIds.remove(attachmentId)
    }

    mutating func reset() {
        processedAttachmentIds = []
        publications = [:]
        observedMetadataByAttachmentId = [:]
        authenticatedMetadataByAttachmentId = [:]
        attachmentArrivalEpochs = [:]
        nextArrivalEpoch = 0
    }
}

/// Prevents a messenger map-state race from starting a second full map transfer
/// while the original SharePlay publication is still arriving. The tracker is
/// session-scoped and uses a monotonic clock so wall-clock changes cannot extend
/// or shorten the suppression window.
struct SharePlayMapRecoveryTracker: Sendable {
    static let suppressionInterval: Duration = .seconds(30)

    private struct Publication: Sendable {
        let version: Int
        let assetVersion: Int
        let sentAt: ContinuousClock.Instant
    }

    private var publications: [UUID: Publication] = [:]

    mutating func recordFullMapPresentation(
        _ model: GameNetworkModel,
        transportSucceeded: Bool,
        at now: ContinuousClock.Instant? = nil
    ) {
        guard transportSucceeded,
              model.sender.isMaster,
              model.type == .reveal,
              model.subType == .show,
              model.data.type == .map,
              model.data.data != nil,
              model.targetId == nil
        else { return }

        let now = now ?? ContinuousClock().now
        removeExpired(at: now)
        publications[model.data.id] = Publication(
            version: model.data.version,
            assetVersion: model.data.effectiveAssetVersion,
            sentAt: now
        )
    }

    mutating func shouldSuppressRecoveryRequest(
        _ model: GameNetworkModel,
        at now: ContinuousClock.Instant? = nil
    ) -> Bool {
        guard !model.sender.isMaster,
              model.type == .reveal,
              model.subType == .mapState,
              model.data.type == .map,
              model.data.data == nil
        else { return false }

        let now = now ?? ContinuousClock().now
        removeExpired(at: now)
        guard let publication = publications[model.data.id] else { return false }

        // A mapState normally has no asset fingerprint, so current players
        // preserve its model version in the request. Structural updates include
        // an asset fingerprint and use the stronger comparison when available.
        if let requestedAssetVersion = model.data.assetVersion {
            return requestedAssetVersion == publication.assetVersion
        }
        return model.data.version == 0 || model.data.version == publication.version
    }

    mutating func reset() {
        publications = [:]
    }

    private mutating func removeExpired(at now: ContinuousClock.Instant) {
        publications = publications.filter { _, publication in
            let age = publication.sentAt.duration(to: now)
            return age >= .zero && age < Self.suppressionInterval
        }
    }
}

@MainActor @Observable
final class RPGSharePlayController {
    private struct PendingSendOperation {
        let id: UUID
        let byteCount: Int
        let operation: @MainActor () async -> Void
    }

    var groupSession: GroupSession<RPGActivity>?
    var isActive: Bool = false
    private(set) var connectionState: SharePlayConnectionState = .inactive
    var canActivateSharePlay: Bool = false
    var stateText: String = "Not Active"

    var gameModel: GameRootModel?
    var packageSender: SharePlaySingleQueuePackageSender?
    var packageReceiver = SharePlayPackageReceiver()

    // Kept alive through session resets so the player can re-join automatically
    // when SharePlay becomes available again for a running game. Only cancelled
    // by stopJoin() when the game itself ends.
    private var joinTask: Task<Void, Never>?
    private var sessionObserverLifecycle = SharePlaySessionObserverLifecycle()
    private var activationTask: Task<Void, Never>?
    private var activationLifecycle = SharePlayActivationLifecycle()

    #if os(visionOS)
    private var systemCoordinator: SystemCoordinator?
    #endif

    private let groupStateObserver = GroupStateObserver()

    private var messenger: GroupSessionMessenger?
    private var sessionLifecycle = SharePlaySessionLifecycle()
    private var participantTracker = SharePlayParticipantTracker()
    private var journalTracker = SharePlayJournalTracker()
    private var mapRecoveryTracker = SharePlayMapRecoveryTracker()
    private let sessionCallbackCoordinator = SharePlaySessionCallbackCoordinator()
    private let sessionTeardownCoordinator = SharePlaySessionTeardownCoordinator()
    // Session-scoped state/participant/message/journal loops, cancelled by reset().
    private var tasks: [UUID: Task<Void, Never>] = [:]
    // Normal Messenger sends are admitted before encoding, then processed in
    // invocation order. This prevents a burst from spawning unbounded parallel
    // Base64 encodes before the package sender can apply its own bounds.
    private var pendingSendOperations: [PendingSendOperation] = []
    private var activeSendOperation: PendingSendOperation?
    private var sendOperationByteCount = 0
    private var sendOperationTask: Task<Void, Never>?
    private var sendOperationGeneration: UInt64 = 0
    private var deferredDeliveryQueue = SharePlayDeferredDeliveryQueue()
    private var deferredPromotionTask: Task<Void, Never>?
    // Publications for one module are serialized, but cleanup of the previous
    // attachment never blocks publication of the next map/photo/PDF/space.
    private let journalPublicationQueue = SharePlayJournalPublicationQueue<GroupSessionJournal.Attachment>()
    private let journalAddLimiter = SharePlayJournalAddLimiter<NetworkModules, GroupSessionJournal.Attachment>()
    private var journal: GroupSessionJournal?

    static let journalAddTimeout: Duration = .seconds(10)
    private static let maxChunkedDeliveryAttempts = 2
    private static let chunkedRetryDelay: Duration = .seconds(1)

    // Lifetime observers — survive session resets; re-created if setup() runs again.
    private var eligibilityTask: Task<Void, Never>?
    #if os(visionOS)
    private var modeChangeTask: Task<Void, Never>?
    #endif

    weak var delegate: SharePlayControllerDelegate?
    weak var playBack: AVPlaybackCoordinator?
    weak var audioCoordinator: AudioListenerCoordinator?

#if os(visionOS)
    weak var tabletopGame: TabletopGame?
#endif

    init() {
        Logger.sharePlay.debug("SharePlay: init")
    }

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

    func setup(gameModel: GameRootModel) {
        Logger.sharePlay.debug("SharePlay: setup")
        self.gameModel = gameModel

        eligibilityTask?.cancel()
        eligibilityTask = Task { [weak self] in
            guard let observer = self?.groupStateObserver else { return }
            for await value in observer.$isEligibleForGroupSession.values {
                guard let self else { return }
                self.canActivateSharePlay = value
            }
        }

        #if os(visionOS)
        // Observe presentation mode changes and apply configuration
        modeChangeTask?.cancel()
        modeChangeTask = Task { [weak self] in
            for await newMode in gameModel.shareState.modeChanged.values {
                guard let self else { return }
                Logger.sharePlay.debug("Presentation mode changed to: \(newMode.rawValue, privacy: .public)")

                // Apply the new spatial template configuration
                self.applyShareState()
            }
        }
        #endif
    }

    func setup(audioCoordinator: AudioListenerCoordinator?) {
        self.audioCoordinator = audioCoordinator
        self.playBack = audioCoordinator?.playbackCoordinator
        guard let groupSession else { return }
        playBack?.coordinateWithSession(groupSession)
    }

    #if os(visionOS)
    func setup(tabletopGame: TabletopGame, gameTableModel: GameTableModel? = nil) {
        self.tabletopGame = tabletopGame
        if let groupSession {
            // `coordinateWithSession` is a synchronous, @MainActor-required TabletopKit call
            // that can block the main thread while the audio session is active (its internal
            // AVAudioSession route/category reconfiguration — SessionCore::setCategory).
            // Apple's own TabletopKit sample defers this exact call inside `Task { @MainActor
            // in }` for the same reason. Do the same so it runs as its own main-actor turn
            // instead of serializing in front of the seating/map/pawn sync work that follows
            // it in `GameTableView.initializeGameIfNeeded()`.
            let task = Task { @MainActor [weak self, weak tabletopGame] in
                guard let self, let tabletopGame, self.tabletopGame === tabletopGame else { return }
                tabletopGame.coordinateWithSession(groupSession)
            }
            trackSessionTask(task, key: Self.coordinateSessionTaskKey)
        }

        if let gameTableModel = gameTableModel {
            setupSeatAssignment(gameTableModel: gameTableModel)
        }
    }
    #endif
}

#if os(visionOS)
private extension RPGSharePlayController {
    static let coordinateSessionTaskKey = UUID()
}
#endif

extension RPGSharePlayController {
    /// Sends to the whole SharePlay session by default. Supplying a participant
    /// ID physically addresses Messenger packages to that active participant;
    /// Journal-backed Audio and Weather repairs remain session-visible by design.
    /// Returns whether a transport or bounded deferred queue accepted the intent.
    @discardableResult
    func sendData(
        _ gameNetworkModel: GameNetworkModel,
        fileJournal: Bool,
        participantId: UUID? = nil
    ) -> Bool {
        Logger.sharePlay.debug("sendData state: \(self.printState(), privacy: .public) model: \(gameNetworkModel.debugDescription, privacy: .private)")
        guard messenger != nil, let sessionId = groupSession?.id else { return false }

        guard let prepared = Self.prepareForTransport(
            gameNetworkModel,
            fileJournal: fileJournal,
            journalAvailable: journal != nil
        ) else { return false }

        // GroupSessionJournal does not expose the participant that authored an
        // attachment. The publisher therefore sends the same logical message's
        // lightweight metadata through Messenger first. Receivers bind that
        // physically attributed announcement to the later Journal callback.
        // Enqueueing is deliberately before Journal publication; delivery may
        // still race, and the receiver retains that race in a bounded queue.
        let journalAnnouncement: GameNetworkModel? = if prepared.usesJournalTransport,
                                                        journalTracker.shouldPublish(model: prepared.model) {
            Self.journalAdmissionMetadata(for: prepared.model)
        } else {
            nil
        }
        let journalAdmissionAlreadyEnqueued: Bool
        if let journalAnnouncement {
            let journalAnnouncementEnqueued = enqueueChunkedSend(
                journalAnnouncement,
                sessionId: sessionId,
                participantId: participantId
            )
            guard journalAnnouncementEnqueued else {
                // Never publish an attachment that receivers cannot attribute.
                // The full Messenger payload preserves the presentation when
                // the lightweight admission cannot enter the bounded queue.
                return enqueueChunkedSend(
                    prepared.model,
                    sessionId: sessionId,
                    participantId: participantId
                )
            }
            journalAdmissionAlreadyEnqueued = true
        } else {
            journalAdmissionAlreadyEnqueued = false
        }

        if prepared.usesJournalTransport,
           let attachmentData = prepared.model.data.data, let journal {
            let moduleKey = prepared.model.data.type
            // `journalMetadata(for:)` hashes the full attachment; this send's model
            // never changes underneath these closures, so hash once and reuse it
            // instead of re-hashing on every branch below.
            let journalMetadataForModel = Self.journalMetadata(for: prepared.model)
            let publication = journalPublicationQueue.enqueue(
                for: moduleKey,
                byteCount: attachmentData.count,
                policy: Self.journalPublicationPolicy(for: prepared.model),
                priority: .userInitiated
            ) { [weak self] in
                guard let self else { return nil }
                guard self.sessionLifecycle.isCurrent(sessionId: sessionId) else { return nil }
                let attachmentSize = Self.formattedByteCount(attachmentData.count)
                self.recordJournalTransport(
                    state: .pending,
                    byteCount: attachmentData.count,
                    for: prepared.model
                )
                Logger.sharePlay.debug("Journal: message \(prepared.model.counter, privacy: .public) attachment \(attachmentSize, privacy: .public) model: \(prepared.model.debugDescription, privacy: .private)")
                if !self.journalTracker.shouldPublish(model: prepared.model) {
                    // Reusing bytes is a storage optimization, not a screen
                    // intent optimization. Every reveal/show still needs a new
                    // lightweight Messenger event so players present it again.
                    // The fresh-publication announcement is control-plane only
                    // and receivers deliberately do not present it. Once this
                    // queued add turns into byte reuse, enqueue a real metadata
                    // presentation even if that earlier announcement succeeded.
                    let metadataAdmissionSucceeded = self.enqueueChunkedSend(
                        journalMetadataForModel,
                        sessionId: sessionId,
                        participantId: participantId
                    )
                    switch SharePlayJournalReuseDisposition(
                        metadataAdmissionSucceeded: metadataAdmissionSucceeded
                    ) {
                    case .reuseExistingAttachment:
                        self.recordJournalTransport(
                            state: .succeeded,
                            byteCount: attachmentData.count,
                            for: prepared.model
                        )
                        Logger.sharePlay.debug("Journal ✓: message \(prepared.model.counter, privacy: .public) reused \(attachmentSize, privacy: .public) \(moduleKey.token, privacy: .public) attachment for \(prepared.model.data.id, privacy: .public)")
                        return nil
                    case .publishFreshAttachment:
                        // A reuse reveal that could not enter Messenger must
                        // fall back to a newly admitted full attachment.
                        Logger.sharePlay.warning("Journal reuse metadata was not admitted for message \(prepared.model.counter, privacy: .public); publishing a fresh \(moduleKey.token, privacy: .public) attachment")
                    }
                }
                let freshJournalAdmissionSucceeded: Bool
                if journalAdmissionAlreadyEnqueued {
                    freshJournalAdmissionSucceeded = true
                } else if let lateAdmission = Self.journalAdmissionMetadata(
                    for: prepared.model
                ) {
                    // The tracker can change while this publication waits in
                    // the per-module queue. If planned reuse becomes a fresh
                    // add, authenticate that anonymous attachment now.
                    freshJournalAdmissionSucceeded = self.enqueueChunkedSend(
                        lateAdmission,
                        sessionId: sessionId,
                        participantId: participantId
                    )
                } else {
                    freshJournalAdmissionSucceeded = false
                }
                guard freshJournalAdmissionSucceeded else {
                    self.recordJournalTransport(
                        state: .failed,
                        byteCount: attachmentData.count,
                        for: prepared.model
                    )
                    _ = self.enqueueChunkedSend(
                        prepared.model,
                        sessionId: sessionId,
                        participantId: participantId
                    )
                    return nil
                }
                let model = journalMetadataForModel
                let outcome = await self.journalAddLimiter.run(
                    for: moduleKey,
                    scope: sessionId,
                    timeout: Self.journalAddTimeout
                ) {
                    try await journal.add(attachmentData, metadata: model)
                } discardLateValue: { [weak self] lateAttachment in
                    guard let self else { return true }
                    return await self.removeJournalAttachment(
                        lateAttachment,
                        from: journal,
                        module: moduleKey,
                        sessionId: sessionId,
                        reason: "late timed-out"
                    )
                }

                switch outcome {
                case .succeeded(let result):
                    guard self.sessionLifecycle.isCurrent(sessionId: sessionId) else {
                        _ = await self.removeJournalAttachment(
                            result,
                            from: journal,
                            module: moduleKey,
                            sessionId: sessionId,
                            reason: "obsolete session"
                        )
                        return nil
                    }
                    return result
                case .failed(let errorDescription):
                    Logger.sharePlay.error("Journal ✕: message \(prepared.model.counter, privacy: .public) cannot add \(attachmentSize, privacy: .public) attachment for module \(prepared.model.data.type.token, privacy: .public) and id: \(prepared.model.data.id, privacy: .public) error: \(errorDescription, privacy: .public)")
                case .timedOut:
                    Logger.sharePlay.error("Journal ⌛: message \(prepared.model.counter, privacy: .public) timed out adding \(moduleKey.token, privacy: .public) attachment; module is degraded to Messenger until the add returns")
                case .unavailable:
                    Logger.sharePlay.warning("Journal bypass: \(moduleKey.token, privacy: .public) still has a quarantined add; using Messenger for message \(prepared.model.counter, privacy: .public)")
                case .cancelled:
                    guard self.sessionLifecycle.isCurrent(sessionId: sessionId) else { return nil }
                    Logger.sharePlay.warning("Journal add cancelled while session remains active; using Messenger for message \(prepared.model.counter, privacy: .public)")
                }

                self.recordJournalTransport(
                    state: .failed,
                    byteCount: attachmentData.count,
                    for: prepared.model
                )
                guard self.sessionLifecycle.isCurrent(sessionId: sessionId) else { return nil }
                let fallbackEnqueued = self.enqueueChunkedSend(
                    prepared.model,
                    sessionId: sessionId,
                    participantId: participantId
                )
                guard fallbackEnqueued else { return nil }
                var retired = false
                if Self.shouldRetireJournalPresentationAfterFallback(prepared.model) {
                    self.journalPublicationQueue.supersedePresentation(for: moduleKey)
                    retired = self.journalPublicationQueue.retireCurrentAttachment(
                        for: moduleKey,
                        priority: .utility
                    ) { [weak self] oldAttachment in
                        guard let self else { return false }
                        return await self.removeJournalAttachment(
                            oldAttachment,
                            from: journal,
                            module: moduleKey,
                            sessionId: sessionId,
                            reason: "Messenger fallback"
                        )
                    }
                }
                if retired {
                    self.gameModel?.attachments[moduleKey] = nil
                }
                return nil
            } commit: { [weak self] result in
                guard let self,
                      self.sessionLifecycle.isCurrent(sessionId: sessionId)
                else { return }
                self.gameModel?.attachments[moduleKey] = result
                self.journalTracker.didPublish(
                    module: moduleKey,
                    itemId: prepared.model.data.id,
                    version: prepared.model.data.effectiveAssetVersion,
                    attachmentId: result.id,
                    metadata: journalMetadataForModel
                )
                self.mapRecoveryTracker.recordFullMapPresentation(
                    prepared.model,
                    transportSucceeded: true
                )
                self.recordJournalTransport(
                    state: .succeeded,
                    byteCount: attachmentData.count,
                    for: prepared.model
                )
                let attachmentSize = Self.formattedByteCount(attachmentData.count)
                Logger.sharePlay.debug("Journal ✓: message \(prepared.model.counter, privacy: .public) added attachment \(result.id, privacy: .public), size \(attachmentSize, privacy: .public)")
            } remove: { [weak self] oldAttachment in
                guard let self else { return false }
                return await self.removeJournalAttachment(
                    oldAttachment,
                    from: journal,
                    module: moduleKey,
                    sessionId: sessionId,
                    reason: "replaced"
                )
            }
            if publication.admission == .rejected {
                recordJournalTransport(
                    state: .failed,
                    byteCount: attachmentData.count,
                    for: prepared.model
                )
                Logger.sharePlay.warning("Journal queue full: falling back to chunked transport for message \(prepared.model.counter, privacy: .public)")
                let fallbackEnqueued = enqueueChunkedSend(
                    prepared.model,
                    sessionId: sessionId,
                    participantId: participantId
                )
                guard fallbackEnqueued else { return false }
                var retired = false
                if Self.shouldRetireJournalPresentationAfterFallback(prepared.model) {
                    journalPublicationQueue.supersedePresentation(for: moduleKey)
                    retired = journalPublicationQueue.retireCurrentAttachment(
                        for: moduleKey,
                        priority: .utility
                    ) { [weak self] oldAttachment in
                        guard let self else { return false }
                        return await self.removeJournalAttachment(
                            oldAttachment,
                            from: journal,
                            module: moduleKey,
                            sessionId: sessionId,
                            reason: "queue-overload fallback"
                        )
                    }
                }
                if retired {
                    gameModel?.attachments[moduleKey] = nil
                }
                return true
            }
            return true
        }

        return enqueueChunkedSend(
            prepared.model,
            sessionId: sessionId,
            participantId: participantId
        )
    }

    /// Authenticates the Journal snapshot already visible to a newly joined
    /// participant. The authoritative master's metadata is enqueued first so it
    /// pins the physical master participant before any player-authored
    /// attachment is announced through that trusted relay.
    @discardableResult
    func reannounceCurrentJournalAdmissions(to participantId: UUID) -> Bool {
        guard let sessionId = groupSession?.id, messenger != nil else { return false }

        let admissions = Self.journalAdmissionsForReplay(
            from: journalTracker.currentJournalMetadata()
        )

        for admission in admissions {
            guard enqueueChunkedSend(
                admission,
                sessionId: sessionId,
                participantId: participantId
            ) else { return false }
        }
        return true
    }

    static func journalAdmissionsForReplay(
        from entries: [(attachmentId: UUID, metadata: GameNetworkModel)]
    ) -> [GameNetworkModel] {
        entries.compactMap { entry in
            journalAdmissionMetadata(fromJournalMetadata: entry.metadata).map {
                (attachmentId: entry.attachmentId, metadata: $0)
            }
        }.sorted { lhs, rhs in
            if lhs.metadata.sender.isMaster != rhs.metadata.sender.isMaster {
                return lhs.metadata.sender.isMaster
            }
            if lhs.metadata.timestamp != rhs.metadata.timestamp {
                return lhs.metadata.timestamp < rhs.metadata.timestamp
            }
            if lhs.metadata.sender.id != rhs.metadata.sender.id {
                return lhs.metadata.sender.id.uuidString < rhs.metadata.sender.id.uuidString
            }
            return lhs.attachmentId.uuidString < rhs.attachmentId.uuidString
        }.map(\.metadata)
    }

    func markJournalAttachmentAuthenticated(_ model: GameNetworkModel) {
        journalTracker.didAuthenticate(model)
    }

    @discardableResult
    private func removeJournalAttachment(
        _ attachment: GroupSessionJournal.Attachment,
        from journal: GroupSessionJournal,
        module: NetworkModules,
        sessionId: UUID,
        reason: String
    ) async -> Bool {
        do {
            let _: Void = try await SharePlayAttachmentLoadRetry.load {
                try await journal.remove(attachment: attachment)
            }
            if sessionLifecycle.isCurrent(sessionId: sessionId) {
                journalTracker.didRemove(attachmentId: attachment.id)
            }
            Logger.sharePlay.debug("Journal ✓: removed \(reason, privacy: .public) \(module.token, privacy: .public) attachment \(attachment.id, privacy: .public)")
            return true
        } catch is CancellationError {
            // Session reset cancels normal cleanup. A timed-out add is retained
            // by the limiter and performs late cleanup in a fresh task.
            return false
        } catch {
            Logger.sharePlay.error("Cannot remove \(reason, privacy: .public) Journal attachment for module \(module.token, privacy: .public) after bounded retries: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    @discardableResult
    private func enqueueChunkedSend(
        _ model: GameNetworkModel,
        sessionId: UUID,
        participantId: UUID?,
        allowDeferral: Bool = true,
        deliveryAttempt: Int = 0
    ) -> Bool {
        let rawPayloadByteCount = model.data.data?.count ?? 0
        guard SharePlayMessengerPayloadBudget.accepts(
            rawPayloadByteCount: rawPayloadByteCount
        ) else {
            recordChunkedTransport(
                count: 0,
                byteCount: rawPayloadByteCount,
                state: .failed,
                for: model
            )
            mapRecoveryTracker.recordFullMapPresentation(
                model,
                transportSucceeded: false
            )
            Logger.sharePlay.error("Chunked ✕: message \(model.counter, privacy: .public) raw payload exceeds the safe \(SharePlayMessengerPayloadBudget.maximumRawPayloadByteCount, privacy: .public)-byte Messenger admission limit")
            return false
        }

        let operationToken = SharePlaySessionOperationToken(
            sessionId: sessionId,
            generation: sendOperationGeneration
        )
        let enqueued = addSendTask(
            byteCount: rawPayloadByteCount
        ) { [weak self] in
            guard let self,
                  operationToken.canCommit(
                    lifecycle: self.sessionLifecycle,
                    currentGeneration: self.sendOperationGeneration,
                    taskIsCancelled: Task.isCancelled
                  ),
                  let sender = self.packageSender
            else { return }
            guard let encodedModel = await Self.encodedData(for: model) else {
                guard operationToken.canCommit(
                    lifecycle: self.sessionLifecycle,
                    currentGeneration: self.sendOperationGeneration,
                    taskIsCancelled: Task.isCancelled
                ) else { return }
                self.recordChunkedTransport(
                    count: 0,
                    byteCount: rawPayloadByteCount,
                    state: .failed,
                    for: model
                )
                return
            }
            guard operationToken.canCommit(
                lifecycle: self.sessionLifecycle,
                currentGeneration: self.sendOperationGeneration,
                taskIsCancelled: Task.isCancelled
            ) else { return }
            guard encodedModel.count <= SharePlaySingleQueuePackageSender.maxMessageByteCount else {
                self.recordChunkedTransport(
                    count: 0,
                    byteCount: encodedModel.count,
                    state: .failed,
                    for: model
                )
                Logger.sharePlay.error("Chunked ✕: message \(model.counter, privacy: .public) encoded beyond Messenger's complete-message limit")
                return
            }
            let outcome = await self.sendChunked(
                encodedModel,
                for: model,
                participantId: participantId,
                using: sender,
                operationToken: operationToken
            )
            guard operationToken.canCommit(
                lifecycle: self.sessionLifecycle,
                currentGeneration: self.sendOperationGeneration,
                taskIsCancelled: Task.isCancelled
            ) else { return }
            self.mapRecoveryTracker.recordFullMapPresentation(
                model,
                transportSucceeded: outcome == .succeeded
            )
            guard outcome == .retryableFailure,
                  deliveryAttempt + 1 < Self.maxChunkedDeliveryAttempts
            else { return }

            let retryAt = ContinuousClock().now.advanced(by: Self.chunkedRetryDelay)
            let admission = self.deferredDeliveryQueue.enqueue(
                model,
                sessionId: sessionId,
                participantId: participantId,
                deliveryAttempt: deliveryAttempt + 1,
                retryNotBefore: retryAt
            )
            if admission.isAccepted {
                Logger.sharePlay.warning("Chunked retry deferred after terminal package failure for message \(model.counter, privacy: .public)")
                self.scheduleDeferredPromotionIfNeeded()
            } else {
                Logger.sharePlay.error("Chunked retry could not be retained for message \(model.counter, privacy: .public): \(String(describing: admission), privacy: .public)")
            }
        }
        if !enqueued {
            if allowDeferral,
               deferredDeliveryQueue.enqueue(
                    model,
                    sessionId: sessionId,
                    participantId: participantId
               ).isAccepted {
                Logger.sharePlay.warning("Chunked queue full: deferred critical message \(model.counter, privacy: .public)")
                return true
            }
            mapRecoveryTracker.recordFullMapPresentation(
                model,
                transportSucceeded: false
            )
            Logger.sharePlay.warning("Chunked queue full: ignored message \(model.counter, privacy: .public)")
        }
        return enqueued
    }

    static func prepareForTransport(
        _ model: GameNetworkModel,
        fileJournal: Bool,
        journalAvailable: Bool
    ) -> (model: GameNetworkModel, usesJournalTransport: Bool)? {
        (
            model,
            usesJournalTransport(
                for: model,
                fileJournal: fileJournal,
                journalAvailable: journalAvailable
            )
        )
    }

    /// The journal slot per module carries broadcast content — the master's
    /// current presentation — plus audio and Weather repairs. Audio repairs are
    /// morphed into untargeted stores, while Weather retains its recipient so a
    /// repair cannot re-present the content on unrelated players. Targeted
    /// answers of the other modules ride a physically participant-targeted
    /// Messenger stream.
    static func usesJournalTransport(for model: GameNetworkModel, fileJournal: Bool, journalAvailable: Bool) -> Bool {
        model.data.type != .value &&
            fileJournal &&
            journalAvailable &&
            model.data.data != nil &&
            (model.targetId == nil || model.data.type == .audio || model.data.type == .weather)
    }

    /// Full reveal/show publications represent screen intent. Once one is
    /// waiting behind an active publication, a newer reveal for the same module
    /// makes that pending intent stale. Repairs and stores remain FIFO because
    /// each may satisfy a different participant or asset request.
    static func journalPublicationPolicy(
        for model: GameNetworkModel
    ) -> SharePlayJournalPublicationPolicy {
        guard model.targetId == nil,
              model.type == .reveal,
              model.subType == .show
        else { return .fifo }

        return switch model.data.type {
        case .map, .photo, .pdf, .space, .weather:
            .latestWins
        default:
            .fifo
        }
    }

    static func journalMetadata(for model: GameNetworkModel) -> GameNetworkModel {
        var metadata = model
        if let payload = model.data.data {
            metadata.journalPayloadDigest = GameNetworkModel.journalDigest(for: payload)
        }
        // Journal developer metadata and Messenger reuse events are real
        // presentations. Only the separate fresh-publication announcement is
        // marked as admission-only.
        metadata.journalAdmissionOnly = nil
        if metadata.data.type == .audio, metadata.targetId != nil {
            // GroupSessionJournal attachments are visible to the whole session.
            // Store the audio on every participant without treating a repair as
            // a new reveal; proxy hosts then forward the same store downstream.
            metadata.type = .store
            metadata.subType = .show
            metadata.targetId = nil
        }
        metadata.data = NetworkCodableDataType(
            id: model.data.id,
            type: model.data.type,
            version: model.data.version,
            data: nil,
            assetVersion: model.data.assetVersion,
            contentVersion: model.data.contentVersion
        )
        return metadata
    }

    /// Returns the physically attributable Messenger half required before a
    /// fresh player Photo/PDF/Space Journal attachment. The stable sender and
    /// message ID are intentionally preserved verbatim for correlation.
    static func playerJournalAdmissionMetadata(
        for model: GameNetworkModel
    ) -> GameNetworkModel? {
        guard model.isPlayerFilePresentationEvent,
              model.data.data != nil,
              model.messageID != nil
        else { return nil }

        var metadata = journalMetadata(for: model)
        metadata.journalAdmissionOnly = true
        return metadata.isPlayerJournalAdmissionMetadata ? metadata : nil
    }

    static func masterJournalAdmissionMetadata(
        for model: GameNetworkModel
    ) -> GameNetworkModel? {
        guard model.isMasterJournalEnvelope,
              model.data.data != nil
        else { return nil }

        // Audio targeting is intentionally normalized by journalMetadata. The
        // exact normalized envelope is both Messenger's admission fingerprint
        // and GroupSessionJournal's developer metadata.
        var metadata = journalMetadata(for: model)
        metadata.journalAdmissionOnly = true
        return metadata.isMasterJournalAdmissionMetadata ? metadata : nil
    }

    static func journalAdmissionMetadata(
        for model: GameNetworkModel
    ) -> GameNetworkModel? {
        if model.sender.isMaster {
            return masterJournalAdmissionMetadata(for: model)
        }
        return playerJournalAdmissionMetadata(for: model)
    }

    /// Rebuilds the participant-attributed Messenger half for an attachment
    /// already present in the Journal. Its original sender, message identity,
    /// timestamp, and payload digest remain unchanged.
    static func journalAdmissionMetadata(
        fromJournalMetadata metadata: GameNetworkModel
    ) -> GameNetworkModel? {
        guard metadata.data.data == nil,
              metadata.messageID != nil,
              metadata.journalPayloadDigest != nil
        else { return nil }

        var admission = metadata
        admission.journalAdmissionOnly = true
        if admission.sender.isMaster {
            return admission.isMasterJournalAdmissionMetadata ? admission : nil
        }
        return admission.isPlayerJournalAdmissionMetadata ? admission : nil
    }

    static func shouldRetireJournalPresentationAfterFallback(_ model: GameNetworkModel) -> Bool {
        model.isFileBackedPresentation || model.isPlayerFilePresentationEvent
    }

    /// Bounds work before encoding and preserves the same FIFO order that the
    /// package sender enforces once bytes have been produced.
    @discardableResult
    private func addSendTask(
        byteCount: Int,
        _ operation: @escaping @MainActor () async -> Void
    ) -> Bool {
        let safeByteCount = max(0, byteCount)
        let outstandingCount = pendingSendOperations.count + (activeSendOperation == nil ? 0 : 1)
        guard outstandingCount < SharePlaySingleQueuePackageSender.maxOutstandingMessages,
              safeByteCount <= SharePlayMessengerPayloadBudget.maximumRawPayloadByteCount,
              sendOperationByteCount <=
                SharePlayMessengerPayloadBudget.maximumOutstandingRawPayloadByteCount - safeByteCount
        else { return false }

        pendingSendOperations.append(PendingSendOperation(
            id: UUID(),
            byteCount: safeByteCount,
            operation: operation
        ))
        sendOperationByteCount += safeByteCount
        startSendOperationTaskIfNeeded()
        return true
    }

    private func startSendOperationTaskIfNeeded() {
        guard sendOperationTask == nil else { return }
        let generation = sendOperationGeneration
        sendOperationTask = Task { @MainActor [weak self] in
            await self?.drainSendOperations(generation: generation)
        }
    }

    private func drainSendOperations(generation: UInt64) async {
        while !Task.isCancelled,
              sendOperationGeneration == generation,
              !pendingSendOperations.isEmpty {
            let pendingOperation = pendingSendOperations.removeFirst()
            activeSendOperation = pendingOperation
            await pendingOperation.operation()
            guard sendOperationGeneration == generation,
                  activeSendOperation?.id == pendingOperation.id
            else { return }
            sendOperationByteCount = max(0, sendOperationByteCount - pendingOperation.byteCount)
            activeSendOperation = nil
            promoteDeferredDeliveries()
        }
        guard sendOperationGeneration == generation else { return }
        activeSendOperation = nil
        sendOperationTask = nil
    }

    private func promoteDeferredDeliveries() {
        while let delivery = deferredDeliveryQueue.first {
            guard sessionLifecycle.isCurrent(sessionId: delivery.sessionId) else {
                deferredDeliveryQueue.removeFirst()
                continue
            }
            guard delivery.isReady(at: ContinuousClock().now) else {
                scheduleDeferredPromotionIfNeeded()
                return
            }
            guard enqueueChunkedSend(
                delivery.model,
                sessionId: delivery.sessionId,
                participantId: delivery.participantId,
                allowDeferral: false,
                deliveryAttempt: delivery.deliveryAttempt
            ) else { return }
            deferredDeliveryQueue.removeFirst()
        }
    }

    private func scheduleDeferredPromotionIfNeeded() {
        guard deferredPromotionTask == nil,
              let delivery = deferredDeliveryQueue.first,
              let retryNotBefore = delivery.retryNotBefore
        else { return }
        let generation = sendOperationGeneration
        let delay = ContinuousClock().now.duration(to: retryNotBefore)
        deferredPromotionTask = Task { @MainActor [weak self] in
            do {
                if delay > .zero {
                    try await Task.sleep(for: delay)
                }
            } catch {
                return
            }
            guard let self,
                  self.sendOperationGeneration == generation
            else { return }
            self.deferredPromotionTask = nil
            self.promoteDeferredDeliveries()
        }
    }

    /// Registers a session-scoped task that reset() cancels. Passing a stable
    /// key replaces (and cancels) the previous task for that key, so repeated
    /// registrations don't accumulate duplicate observers.
    func trackSessionTask(_ task: Task<Void, Never>, key: UUID = UUID()) {
        tasks[key]?.cancel()
        tasks[key] = task
    }

    /// Encoding can include multi-megabyte Base64 payloads and has no UI
    /// dependency. Defer it until Messenger is actually needed and keep it off
    /// the main actor.
    @concurrent
    private static func encodedData(for model: GameNetworkModel) async -> Data? {
        guard !Task.isCancelled else { return nil }
        return model.encodeData()
    }

    /// Reassembly and JSON decoding are both proportional to the encoded byte
    /// count and can be multi-megabyte work. Keep the complete operation off
    /// the main actor and return only the decoded value plus its log size.
    @concurrent
    static func decodedMessage(
        from package: SharePlayCompletedPackage
    ) async -> (model: GameNetworkModel, byteCount: Int)? {
        guard !Task.isCancelled else { return nil }
        let data = package.reassembledData()
        guard !Task.isCancelled,
              let model = GameNetworkModel.decodeData(of: data)
        else { return nil }
        return (model, data.count)
    }

    @discardableResult
    private func sendChunked(
        _ data: Data,
        for model: GameNetworkModel,
        participantId: UUID?,
        using sender: SharePlaySingleQueuePackageSender,
        operationToken: SharePlaySessionOperationToken
    ) async -> SharePlayChunkedDeliveryOutcome {
        guard operationToken.canCommit(
            lifecycle: sessionLifecycle,
            currentGeneration: sendOperationGeneration,
            taskIsCancelled: Task.isCancelled
        ) else { return .cancelled }
        let packageCount = sender.packageCount(for: data)
        let size = Self.formattedByteCount(data.count)
        recordChunkedTransport(
            count: packageCount,
            byteCount: data.count,
            state: .pending,
            for: model
        )
        Logger.sharePlay.debug("Chunked: message \(model.counter, privacy: .public), packages \(packageCount, privacy: .public), encoded size \(size, privacy: .public)")
        do {
            try await sender.send(data: data, participantId: participantId)
            guard operationToken.canCommit(
                lifecycle: sessionLifecycle,
                currentGeneration: sendOperationGeneration,
                taskIsCancelled: Task.isCancelled
            ) else { return .cancelled }
            recordChunkedTransport(
                count: packageCount,
                byteCount: data.count,
                state: .succeeded,
                for: model
            )
            Logger.sharePlay.debug("Chunked ✓: message \(model.counter, privacy: .public), packages \(packageCount, privacy: .public)")
            return .succeeded
        } catch is CancellationError {
            return .cancelled
        } catch SharePlayPackageSenderError.messageTooLarge {
            guard operationToken.canCommit(
                lifecycle: sessionLifecycle,
                currentGeneration: sendOperationGeneration,
                taskIsCancelled: Task.isCancelled
            ) else { return .cancelled }
            recordChunkedTransport(
                count: packageCount,
                byteCount: data.count,
                state: .failed,
                for: model
            )
            Logger.sharePlay.error("Chunked ✕: message \(model.counter, privacy: .public) exceeds Messenger's complete-message limit")
            return .terminalFailure
        } catch {
            guard operationToken.canCommit(
                lifecycle: sessionLifecycle,
                currentGeneration: sendOperationGeneration,
                taskIsCancelled: Task.isCancelled
            ) else { return .cancelled }
            // Missing one package leaves the receiver waiting forever. Keep the
            // failure visible after the sender has exhausted its bounded retry.
            recordChunkedTransport(
                count: packageCount,
                byteCount: data.count,
                state: .failed,
                for: model
            )
            Logger.sharePlay.error("Chunked ✕: message \(model.counter, privacy: .public), packages \(packageCount, privacy: .public), error: \(error.localizedDescription, privacy: .public)")
            return .retryableFailure
        }
    }

    private func recordJournalTransport(
        state: SharePlayJournalTransportState,
        byteCount: Int,
        for model: GameNetworkModel
    ) {
        updateTransportLog(for: model) { transport in
            transport.journal = SharePlayJournalTransportLog(byteCount: byteCount, state: state)
        }
    }

    private func recordChunkedTransport(
        count: Int,
        byteCount: Int,
        state: SharePlayChunkTransportState,
        for model: GameNetworkModel
    ) {
        updateTransportLog(for: model) { transport in
            transport.chunked = SharePlayChunkTransportLog(
                count: count,
                byteCount: byteCount,
                state: state
            )
        }
    }

    private func updateTransportLog(
        for model: GameNetworkModel,
        update: (inout SharePlayTransportLog) -> Void
    ) {
        guard let log = gameModel?.logData[model.counter],
              log.type == model.type,
              log.subType == model.subType,
              log.module == model.data.type,
              log.itemId == model.data.id
        else { return }

        var transport = log.sharePlayTransport
        update(&transport)
        log.sharePlayTransport = transport
    }

    nonisolated private static func formattedByteCount(_ byteCount: Int) -> String {
        Int64(byteCount).formatted(.byteCount(style: .file))
    }

    func reset() {
        Logger.sharePlay.debug("SharePlay: reset state: \(self.printState(), privacy: .public)")
        cancelActivation()
        isActive = false
        messenger = nil
        sendOperationGeneration &+= 1
        sendOperationTask?.cancel()
        sendOperationTask = nil
        deferredPromotionTask?.cancel()
        deferredPromotionTask = nil
        pendingSendOperations = []
        activeSendOperation = nil
        sendOperationByteCount = 0
        deferredDeliveryQueue.reset()
        packageSender?.cancelAll()
        packageSender = nil
        journal = nil
        sessionLifecycle.reset()
        participantTracker.reset()
        journalTracker.reset()
        mapRecoveryTracker.reset()
        journalPublicationQueue.cancelAll()
        journalAddLimiter.cancelAll()
        tasks.values.forEach { $0.cancel() }
        tasks = [:]
        packageReceiver.reset()
        gameModel?.attachments = [:]
        if groupSession != nil {
            groupSession?.leave()
            groupSession = nil
        }
        #if os(visionOS)
        tabletopGame?.detachNetworkCoordinator()
        systemCoordinator = nil
        gameModel?.shareState.isSharePlayActive = false
        gameModel?.shareState.groupImmersionActive = false
        #endif
    }

    func startSharing(with name: String?, image: AKImage?) {
        Logger.sharePlay.debug("Start Sharing state: \(self.printState(), privacy: .public)")
        #if os(macOS)
            if let image {
                var imageRect = CGRect(x: 0, y: 0, width: image.size.width, height: image.size.height)
                let imageRef = image.cgImage(forProposedRect: &imageRect, context: nil, hints: nil)
                RPGActivity.titleImage = imageRef
            }
        #else
            RPGActivity.titleImage = image?.cgImage
        #endif
        activationTask?.cancel()
        if let groupSession {
            activationLifecycle.cancelCurrent()
            activationTask = nil
            let activity = RPGActivity(adventureTitle: name ?? "Adventure")
            Logger.sharePlay.debug("GroupSession active state: \(self.printState(), privacy: .public)")
            groupSession.activity = activity
        } else {
            let activityId = UUID()
            let token = activationLifecycle.begin(activityId: activityId)
            let activity = RPGActivity(
                adventureTitle: name ?? "Adventure",
                activationId: activityId
            )
            activationTask = Task { [weak self] in
                do {
                    let activated = try await activity.activate()
                    guard let self else { return }
                    let canCommit = self.activationLifecycle.canCommit(
                        token: token,
                        taskIsCancelled: Task.isCancelled
                    )
                    self.activationLifecycle.didFinish(
                        token: token,
                        activated: activated
                    )
                    self.stopCleanupSessionObserverIfPossible()
                    guard canCommit else { return }
                    self.activationTask = nil
                    Logger.sharePlay.debug("Activate state: \(self.printState(), privacy: .public)")
                } catch {
                    guard let self else { return }
                    let canCommit = self.activationLifecycle.canCommit(
                        token: token,
                        taskIsCancelled: Task.isCancelled
                    )
                    self.activationLifecycle.didFinish(token: token, activated: false)
                    self.stopCleanupSessionObserverIfPossible()
                    guard canCommit else { return }
                    self.activationTask = nil
                    Logger.sharePlay.error("Activate error \(error.localizedDescription) state: \(self.printState(), privacy: .public)")
                }
            }
        }
    }

    func joinGame() {
        Logger.sharePlay.debug("Join state: \(self.printState(), privacy: .public)")
        connectionState = .waiting
        joinTask?.cancel()
        let observerToken = sessionObserverLifecycle.start(acceptsSessions: true)
        startSessionObserver(token: observerToken)
    }

    private func startSessionObserver(token observerToken: SharePlaySessionObserverToken) {
        // Store in joinTask (not tasks) so reset() does not cancel it.
        // The for-await loop stays alive across session invalidations and picks
        // up the next session automatically when the player re-joins the call.
        joinTask = Task { [weak self] in
            for await session in RPGActivity.sessions() {
                guard let self else { return }
                guard self.sessionObserverLifecycle.isCurrent(
                    token: observerToken,
                    taskIsCancelled: Task.isCancelled
                ) else { return }
                switch self.activationLifecycle.dispositionForSession(
                    activityId: session.activity.activationId,
                    acceptsSessions: self.sessionObserverLifecycle.acceptsSessions
                ) {
                case .configure:
                    break
                case .leave:
                    Logger.sharePlay.debug("Leaving session rejected by activation lifecycle \(session.id, privacy: .public)")
                    session.leave()
                    continue
                case .leaveAndStopCleanup:
                    Logger.sharePlay.debug("Leaving final session from stopped activation \(session.id, privacy: .public)")
                    session.leave()
                    self.sessionObserverLifecycle.stop()
                    self.joinTask = nil
                    return
                }
                guard self.sessionObserverLifecycle.canConfigure(
                    token: observerToken,
                    taskIsCancelled: Task.isCancelled
                ) else {
                    session.leave()
                    return
                }
                Logger.sharePlay.debug("Session \(session.description, privacy: .public) state: \(self.printState(), privacy: .public)")

                await self.configureGroupSession(session)
                guard self.sessionObserverLifecycle.canConfigure(
                    token: observerToken,
                    taskIsCancelled: Task.isCancelled
                ) else { return }
                #if os(visionOS)
                await self.configureSystemCoordinator(for: session)
                #endif
            }
        }
    }

    func stopJoin() {
        Logger.sharePlay.debug("SharePlay: stopJoin")
        connectionState = .inactive
        // Revoke and cancel the normal observer before creating a cleanup-only
        // replacement. An already-admitted configure await cannot commit with
        // its obsolete generation afterward.
        sessionObserverLifecycle.stop()
        joinTask?.cancel()
        joinTask = nil
        cancelActivation()
        if activationLifecycle.hasObsoleteActivities {
            // Keep at most one sessions() subscriber alive in cleanup-only
            // mode so a non-cooperative late activation can be explicitly left.
            let cleanupToken = sessionObserverLifecycle.start(acceptsSessions: false)
            startSessionObserver(token: cleanupToken)
        }
    }

    private func cancelActivation() {
        activationTask?.cancel()
        activationTask = nil
        activationLifecycle.cancelCurrent()
    }

    private func stopCleanupSessionObserverIfPossible() {
        guard !sessionObserverLifecycle.acceptsSessions,
              !activationLifecycle.hasObsoleteActivities
        else { return }
        sessionObserverLifecycle.stop()
        joinTask?.cancel()
        joinTask = nil
    }

    func configureGroupSession(_ groupSession: GroupSession<RPGActivity>) async {
        Logger.sharePlay.debug("Configure Session \(groupSession.description, privacy: .public) state: \(self.printState(), privacy: .public)")

        // An invalidated-state worker resets synchronously, then performs its
        // delegate cleanup asynchronously. Do not let sessions() configure a
        // replacement inside that suspension window.
        await sessionTeardownCoordinator.waitForPendingTeardown()
        guard !Task.isCancelled else { return }

        if self.groupSession?.id == groupSession.id,
           messenger != nil,
           journal != nil,
           packageSender != nil {
            Logger.sharePlay.debug("Configure Session ignored duplicate \(groupSession.id, privacy: .public)")
            return
        }
        if self.groupSession != nil || messenger != nil || journal != nil || packageSender != nil {
            // RPGActivity.sessions() can yield a replacement before the old
            // state loop reports invalidation. Capture its physical roster,
            // cancel every old worker, then await all loss handling before any
            // replacement loop can announce ready/replay state.
            let previousSessionId = self.groupSession?.id
            let teardownEvents = participantTracker.drainSessionTeardownEvents()
            let teardownDelegate = delegate
            let callbackCoordinator = sessionCallbackCoordinator
            let teardown = sessionTeardownCoordinator.start {
                if let previousSessionId {
                    await callbackCoordinator.waitUntilIdle(sessionId: previousSessionId)
                }
                await Self.reportSessionTeardown(teardownEvents, to: teardownDelegate)
            }
            reset()
            await sessionTeardownCoordinator.waitForCompletion(of: teardown)
            guard !Task.isCancelled else { return }
        }

        sessionLifecycle.prepare(sessionId: groupSession.id)
        participantTracker.reset()
        mapRecoveryTracker.reset()
        isActive = false
        self.groupSession = groupSession
        connectionState = .waiting
        let messenger = GroupSessionMessenger(session: groupSession)
        self.messenger = messenger
        // Bind every in-flight package stream to the messenger for this exact
        // session. A later session replacement must not split one UUID stream
        // across two GroupSessionMessenger instances.
        packageSender = SharePlaySingleQueuePackageSender { package, participantId in
            if let participantId {
                guard let participant = groupSession.activeParticipants.first(where: { $0.id == participantId }) else {
                    throw SharePlayPackageDeliveryError.participantNotActive(participantId)
                }
                try await messenger.send(package, to: .only([participant]))
            } else {
                try await messenger.send(package)
            }
        }
        let journal = GroupSessionJournal(session: groupSession)
        self.journal = journal

        #if os(visionOS)
        gameModel?.shareState.isSharePlayActive = false
        #endif
        let stateTask = Task { [weak self] in
            for await state in groupSession.$state.values {
                guard let self else { return }
                guard !Task.isCancelled,
                      self.sessionLoopIsCurrent(sessionId: groupSession.id)
                else { return }
                let stateDescription = self.printState()
                Logger.sharePlay.debug("Session state: \(stateDescription, privacy: .public)")
                self.stateText = stateDescription
                switch state {
                case .waiting:
                    self.connectionState = .waiting
                case .joined:
                    self.isActive = true
                    self.connectionState = .joined
                    #if os(visionOS)
                    self.gameModel?.shareState.isSharePlayActive = true
                    #endif
                    if self.sessionLifecycle.didEnterJoinedState(sessionId: groupSession.id) {
                        guard await self.performSessionCallback(sessionId: groupSession.id, operation: {
                            await self.delegate?.sharePlaySessionConfigured()
                        }) else { return }

                        let added = self.participantTracker.sessionDidJoin(
                            activeParticipantIds: Set(groupSession.activeParticipants.map(\.id)),
                            localParticipantId: groupSession.localParticipant.id
                        )
                        for participantId in added.sorted(by: { $0.uuidString < $1.uuidString }) {
                            guard await self.performSessionCallback(sessionId: groupSession.id, operation: {
                                await self.delegate?.sharePlayJoinedPlayer(id: participantId)
                            }) else { return }
                        }
                    }
                case .invalidated:
                    self.connectionState = .disconnected
                    let teardownEvents = self.participantTracker.drainSessionTeardownEvents()
                    let teardownDelegate = self.delegate
                    let callbackCoordinator = self.sessionCallbackCoordinator
                    // Publish the pending operation before reset. A replacement
                    // yielded by sessions() will now observe and await it even
                    // while the first delegate callback is suspended.
                    let teardown = self.sessionTeardownCoordinator.start {
                        await callbackCoordinator.waitUntilIdle(sessionId: groupSession.id)
                        await Self.reportSessionTeardown(teardownEvents, to: teardownDelegate)
                    }
                    self.groupSession = nil
                    self.reset()
                    await self.sessionTeardownCoordinator.waitForCompletion(of: teardown)
                    return
                @unknown default:
                    break
                }
            }
        }
        tasks[UUID()] = stateTask

        // Track transport identities directly. An initial participant snapshot
        // may arrive before `.joined`; the tracker retains it and the state loop
        // replays those participants exactly once after Messenger is ready.
        let participantTask = Task { [weak self] in
            guard let self else { return }
            for await _ in groupSession.$activeParticipants.values {
                guard !Task.isCancelled,
                      self.sessionLoopIsCurrent(sessionId: groupSession.id)
                else { return }
                // Treat each stream element as a wake-up signal only, and re-read
                // `groupSession.activeParticipants` live rather than trusting the
                // value the stream delivered. `stateTask`'s `.joined` handler also
                // does a live read (to replay anyone already present the instant
                // we join); the two run as independently-scheduled Tasks with no
                // relative-ordering guarantee, so a backlogged, already-superseded
                // element delivered here could otherwise be diffed against roster
                // state the live read on the other task had already advanced past,
                // producing a spurious "removed" for a still-connected participant.
                // Reading fresh here makes every diff use
                // the same single source of truth: a stale queued wake-up becomes,
                // at worst, a harmless no-op re-check instead of a wrong diff.
                let activeParticipants = groupSession.activeParticipants
                let change = self.participantTracker.participantsChanged(
                    activeParticipantIds: Set(activeParticipants.map(\.id)),
                    localParticipantId: groupSession.localParticipant.id,
                    sessionIsJoined: self.isActive
                )
                Logger.sharePlay.debug("Session Participants active: \(activeParticipants.debugDescription, privacy: .public) added: \(change.added.debugDescription, privacy: .public) removed: \(change.removed.debugDescription, privacy: .public)")
                for participantId in change.removed.sorted(by: { $0.uuidString < $1.uuidString }) {
                    guard await self.performSessionCallback(sessionId: groupSession.id, operation: {
                        await self.delegate?.sharePlayLostPlayer(id: participantId)
                    }) else { return }
                }
                for participantId in change.added.sorted(by: { $0.uuidString < $1.uuidString }) {
                    guard await self.performSessionCallback(sessionId: groupSession.id, operation: {
                        await self.delegate?.sharePlayJoinedPlayer(id: participantId)
                    }) else { return }
                }
            }
        }
        tasks[UUID()] = participantTask

        let messageTask = Task { [weak self] in
            for await (message, context) in messenger.messages(of: PackageMessage.self) {
                guard let self else { return }
                guard !Task.isCancelled,
                      self.sessionLifecycle.isCurrent(sessionId: groupSession.id)
                else { return }
                Logger.sharePlay.debug("Received Update Message \(message.uuid, privacy: .public): \(message.count, privacy: .public) - \(message.total, privacy: .public) from \(context.source.id, privacy: .public)")
                if let completedPackage = self.packageReceiver.received(
                    package: message,
                    from: context.source.id
                ),
                   let decodedMessage = await Self.decodedMessage(from: completedPackage) {
                    let size = Self.formattedByteCount(decodedMessage.byteCount)
                    Logger.sharePlay.debug("Chunked ✓: received \(message.total, privacy: .public) packages, assembled size \(size, privacy: .public) from \(context.source.id, privacy: .public)")
                    guard !Task.isCancelled,
                          self.sessionLifecycle.isCurrent(sessionId: groupSession.id)
                    else { return }
                    let gameModel = decodedMessage.model
                    if self.mapRecoveryTracker.shouldSuppressRecoveryRequest(gameModel) {
                        Logger.sharePlay.debug("Ignored recent map recovery request for \(gameModel.data.id, privacy: .public) from \(context.source.id, privacy: .public)")
                        continue
                    }
                    guard await self.performSessionCallback(sessionId: groupSession.id, operation: {
                        await self.delegate?.handleUpdate(
                            gameModel,
                            id: completedPackage.sourceParticipantId
                        )
                    }) else { return }
                }
            }
        }
        tasks[UUID()] = messageTask
        let journalTask = Task { [weak self] in
            for await attachment in journal.attachments {
                guard let self else { return }
                guard !Task.isCancelled,
                      self.sessionLifecycle.isCurrent(sessionId: groupSession.id)
                else { return }
                await self.handle(attachment, sessionId: groupSession.id)
            }
        }
        tasks[UUID()] = journalTask

        // Calling join() establishes the ordering guarantee documented by
        // GroupActivities: synchronization requested after this call is queued
        // until the session reaches .joined.
        // Called via Task.detached to avoid blocking the main thread while the
        // audio session is active (SessionCore warning).
        let sessionToJoin = groupSession
        let sessionJoinTask = Task.detached {
            guard !Task.isCancelled else { return }
            sessionToJoin.join()
            if Task.isCancelled {
                // Cancellation can race the synchronous join after its preflight
                // check. Restore the reset postcondition for the obsolete session.
                sessionToJoin.leave()
            }
        }
        // reset() now owns cancellation of a delayed join for this session.
        tasks[UUID()] = sessionJoinTask
        sessionLifecycle.didRequestJoin(sessionId: groupSession.id)
        playBack?.coordinateWithSession(groupSession)
        #if os(visionOS)
        // This API is synchronous. Calling it directly keeps coordination in
        // the configured session's lifetime instead of spawning an obsolete,
        // untracked task that reset() cannot cancel.
        guard !Task.isCancelled,
              sessionLoopIsCurrent(sessionId: groupSession.id)
        else { return }
        tabletopGame?.coordinateWithSession(groupSession)

        if tabletopGame != nil {
            if let gameTableModel = gameModel?.gameTableModel {
                setupSeatAssignment(gameTableModel: gameTableModel)
            } else {
                Logger.sharePlay.debug("GameTableModel not available at session configure time — seats assigned later")
            }
        }
        #endif
    }

    private func sessionLoopIsCurrent(sessionId: UUID) -> Bool {
        sessionLifecycle.isCurrent(sessionId: sessionId) &&
            groupSession?.id == sessionId
    }

    private func performSessionCallback(
        sessionId: UUID,
        operation: @MainActor () async -> Void
    ) async -> Bool {
        await sessionCallbackCoordinator.perform(
            sessionId: sessionId,
            shouldContinue: { [weak self] in
                self?.sessionLoopIsCurrent(sessionId: sessionId) == true
            },
            operation: operation
        )
    }

    func reportSessionTeardown(
        _ events: [SharePlaySessionTeardownEvent]
    ) async {
        await Self.reportSessionTeardown(events, to: delegate)
    }

    static func reportSessionTeardown(
        _ events: [SharePlaySessionTeardownEvent],
        to delegate: (any SharePlayControllerDelegate)?
    ) async {
        for event in events {
            switch event {
            case .lostParticipant(let participantId):
                await delegate?.sharePlayLostPlayer(id: participantId)
            case .lostConnection:
                await delegate?.sharePlayLostConnection()
            }
        }
    }

    func handle(_ attachments: GroupSessionJournal.Attachments.Element, sessionId: UUID) async {
        guard !Task.isCancelled,
              sessionLifecycle.isCurrent(sessionId: sessionId)
        else { return }
        journalTracker.reconcile(attachmentIds: Set(attachments.map(\.id)))
        let timestampAcceptanceNow = Date.now.timeIntervalSince1970
        var currentAttachments: [NetworkModules: GroupSessionJournal.Attachment] = [:]
        var entries: [(
            attachment: GroupSessionJournal.Attachment,
            metadata: GameNetworkModel,
            arrivalEpoch: UInt64
        )] = []

        for attachment in attachments {
            do {
                let metadata = try await attachment.loadMetadata(of: GameNetworkModel.self)
                guard !Task.isCancelled,
                      sessionLifecycle.isCurrent(sessionId: sessionId)
                else { return }
                guard Self.shouldLoadJournalAttachmentData(
                    for: metadata,
                    now: timestampAcceptanceNow
                ) else {
                    Logger.sharePlay.warning("Journal: skipped invalid presentation timestamp \(metadata.timestamp, privacy: .public) attachment \(attachment.id, privacy: .public)")
                    continue
                }
                journalTracker.didObserve(
                    attachmentId: attachment.id,
                    metadata: metadata
                )
                entries.append((
                    attachment,
                    metadata,
                    journalTracker.arrivalEpoch(for: attachment.id)
                ))
            } catch is CancellationError {
                return
            } catch let error {
                guard !Task.isCancelled,
                      sessionLifecycle.isCurrent(sessionId: sessionId)
                else { return }
                Logger.sharePlay.error("Exception in load attachment metaData \(error.localizedDescription, privacy: .public)")
            }
        }

        // A live snapshot gives newly observed attachments a later causal epoch,
        // regardless of which player's private counter happens to be larger. A
        // late join can observe several publications at once; those entries use
        // sender-local counters only within one sender and a stable attachment-ID
        // tie-break across senders.
        let orderedEntries = Self.orderedJournalEntries(in: entries.map {
            (
                attachmentId: $0.attachment.id,
                metadata: $0.metadata,
                arrivalEpoch: $0.arrivalEpoch
            )
        })
        let orderByAttachmentId = Dictionary(uniqueKeysWithValues:
            orderedEntries.enumerated().map { ($0.element.attachmentId, $0.offset) }
        )
        entries.sort {
            orderByAttachmentId[$0.attachment.id, default: .max] <
                orderByAttachmentId[$1.attachment.id, default: .max]
        }
        let latestPresentationAttachmentId = Self.latestJournalPresentationAttachmentId(
            in: entries.map {
                (
                    attachmentId: $0.attachment.id,
                    metadata: $0.metadata,
                    arrivalEpoch: $0.arrivalEpoch
                )
            },
            now: timestampAcceptanceNow
        )

        for entry in entries {
            guard !Task.isCancelled,
                  sessionLifecycle.isCurrent(sessionId: sessionId)
            else { return }
            let attachment = entry.attachment
            var metadata = entry.metadata
            currentAttachments[metadata.data.type] = attachment
            // Recorded for every attachment currently in the journal — including
            // our own — so the debug attachments list reflects what's actually
            // published, regardless of who authored it. Sorted processing leaves
            // the newest publication in each module slot.
            gameModel?.metaDataAttachments[metadata.data.type] = metadata.data.id
            // journal.attachments emits the FULL current set on every change.
            // Track processed system attachment IDs separately from the current
            // module slot. A removed/re-added item gets a new attachment ID and
            // is therefore processed again.
            guard journalTracker.shouldProcess(attachmentId: attachment.id) else { continue }
            if metadata.sender.id == gameModel?.gameConfig.id { continue }
            if Self.isJournalPresentation(metadata),
               latestPresentationAttachmentId != attachment.id {
                // The replacement has already been published. Loading or
                // repairing this superseded attachment could make an old map
                // arrive after and overwrite the current presentation.
                Logger.sharePlay.debug("Journal: skipped superseded message \(metadata.counter, privacy: .public) attachment \(attachment.id, privacy: .public)")
                continue
            }
            Logger.sharePlay.debug("Attachments \(metadata.counter, privacy: .public)")
            do {
                let data = try await SharePlayAttachmentLoadRetry.load {
                    try await attachment.load(Data.self)
                }
                guard !Task.isCancelled,
                      sessionLifecycle.isCurrent(sessionId: sessionId)
                else { return }
                let size = Self.formattedByteCount(data.count)
                Logger.sharePlay.debug("Journal ✓: received message \(metadata.counter, privacy: .public) attachment \(attachment.id, privacy: .public), size \(size, privacy: .public)")
                metadata.data = NetworkCodableDataType(
                    id: metadata.data.id,
                    type: metadata.data.type,
                    version: metadata.data.version,
                    data: data,
                    assetVersion: metadata.data.assetVersion,
                    contentVersion: metadata.data.contentVersion
                )
                guard await performSessionCallback(sessionId: sessionId, operation: {
                    await delegate?.handleFileUpdate(metadata)
                }) else { return }
            } catch is CancellationError {
                return
            } catch let error {
                guard !Task.isCancelled,
                      sessionLifecycle.isCurrent(sessionId: sessionId)
                else { return }
                // GroupSessionJournal can publish developer metadata while the
                // CloudAsset still reports `uploadInProgress`. Keep this ID
                // retryable for the next journal snapshot after the short local
                // retry window, and use the messenger repair path immediately.
                journalTracker.retryProcessing(attachmentId: attachment.id)
                Logger.sharePlay.warning("Journal attachment \(attachment.id, privacy: .public) remained unavailable after retries: \(error.localizedDescription, privacy: .public). Requesting messenger recovery.")
                // Reveal metadata can still use an exact-version local copy.
                // Store/update metadata needs an explicit byte request because
                // its normal handlers may ACK or fail without asking again.
                guard await performSessionCallback(sessionId: sessionId, operation: {
                    await delegate?.handleFileLoadFailure(metadata)
                }) else { return }
            }
        }

        guard !Task.isCancelled,
              sessionLifecycle.isCurrent(sessionId: sessionId)
        else { return }
        gameModel?.attachments = currentAttachments
    }

    /// Pairwise precedence used by focused comparisons. Full snapshots must use
    /// `orderedJournalEntries(in:)`, which can honor causal reply edges without
    /// forming a comparison cycle with a third, independently timestamped event.
    /// Arrival epochs remain the primary causal boundary.
    static func journalEntryComesBefore(
        metadata lhs: GameNetworkModel,
        attachmentId lhsAttachmentId: UUID,
        arrivalEpoch lhsArrivalEpoch: UInt64,
        metadata rhs: GameNetworkModel,
        attachmentId rhsAttachmentId: UUID,
        arrivalEpoch rhsArrivalEpoch: UInt64
    ) -> Bool {
        if lhsArrivalEpoch != rhsArrivalEpoch {
            return lhsArrivalEpoch < rhsArrivalEpoch
        }
        if isCausalJournalCorrection(lhs, replyingTo: rhs) {
            return false
        }
        if isCausalJournalCorrection(rhs, replyingTo: lhs) {
            return true
        }
        return journalMetadataComesBefore(
            metadata: lhs,
            attachmentId: lhsAttachmentId,
            metadata: rhs,
            attachmentId: rhsAttachmentId
        )
    }

    /// Produces a stable total order while honoring explicit causal corrections.
    /// A pairwise comparator alone cannot safely express `player -> master`
    /// when a third unrelated event has a timestamp between their skewed clocks;
    /// that would form a comparison cycle. Within each arrival epoch this uses a
    /// deterministic topological order, with the ordinary timestamp/sender key
    /// selecting among events whose causal dependencies are already satisfied.
    static func orderedJournalEntries(
        in entries: [(
            attachmentId: UUID,
            metadata: GameNetworkModel,
            arrivalEpoch: UInt64
        )]
    ) -> [(
        attachmentId: UUID,
        metadata: GameNetworkModel,
        arrivalEpoch: UInt64
    )] {
        var ordered: [(
            attachmentId: UUID,
            metadata: GameNetworkModel,
            arrivalEpoch: UInt64
        )] = []

        for epoch in Set(entries.map(\.arrivalEpoch)).sorted() {
            let epochEntries = entries.filter { $0.arrivalEpoch == epoch }
            let dependencies = Dictionary(uniqueKeysWithValues: epochEntries.map { child in
                let parentAttachmentIds = Set(epochEntries.compactMap { parent in
                    isCausalJournalCorrection(child.metadata, replyingTo: parent.metadata) ?
                        parent.attachmentId : nil
                })
                return (child.attachmentId, parentAttachmentIds)
            })
            var emittedAttachmentIds: Set<UUID> = []
            var remaining = epochEntries

            while !remaining.isEmpty {
                let eligible = remaining.filter {
                    dependencies[$0.attachmentId, default: []]
                        .isSubset(of: emittedAttachmentIds)
                }
                // A malformed cycle must not make the snapshot unprocessable.
                // Master-only correction edges cannot form one under normal
                // admission, but the deterministic base order fails closed.
                let candidates = eligible.isEmpty ? remaining : eligible
                guard let next = candidates.min(by: { lhs, rhs in
                    journalMetadataComesBefore(
                        metadata: lhs.metadata,
                        attachmentId: lhs.attachmentId,
                        metadata: rhs.metadata,
                        attachmentId: rhs.attachmentId
                    )
                }) else { break }

                ordered.append(next)
                emittedAttachmentIds.insert(next.attachmentId)
                remaining.removeAll { $0.attachmentId == next.attachmentId }
            }
        }
        return ordered
    }

    static func latestJournalPresentationAttachmentId(
        in entries: [(
            attachmentId: UUID,
            metadata: GameNetworkModel,
            arrivalEpoch: UInt64
        )],
        now: TimeInterval = Date.now.timeIntervalSince1970
    ) -> UUID? {
        // Invalid current timestamps are poisoned ordering input, not legacy
        // envelopes. Remove them before choosing the newest causal epoch.
        let presentations = entries.filter {
            isJournalPresentation($0.metadata) &&
                GameNetworkModel.acceptsEventTimestamp($0.metadata.timestamp, now: now)
        }
        guard let latestArrivalEpoch = presentations.map(\.arrivalEpoch).max() else {
            return nil
        }

        // Only publications newly observed together need a cross-publisher
        // choice. Earlier epochs were already delivered and the player's
        // presentation-intent state machine retains their ordering.
        let latestEpochPresentations = presentations.filter {
            $0.arrivalEpoch == latestArrivalEpoch
        }
        return orderedJournalEntries(in: latestEpochPresentations).last?.attachmentId
    }

    /// Metadata is cheap to inspect, so reject poisoned presentation ordering
    /// before loading any Journal bytes. Non-presentation attachments do not
    /// participate in wall-clock last-wins ordering and remain unaffected.
    static func shouldLoadJournalAttachmentData(
        for metadata: GameNetworkModel,
        now: TimeInterval = Date.now.timeIntervalSince1970
    ) -> Bool {
        !isJournalPresentation(metadata) ||
            GameNetworkModel.acceptsEventTimestamp(metadata.timestamp, now: now)
    }

    private static func journalMetadataComesBefore(
        metadata lhs: GameNetworkModel,
        attachmentId lhsAttachmentId: UUID,
        metadata rhs: GameNetworkModel,
        attachmentId rhsAttachmentId: UUID
    ) -> Bool {
        let lhsTimestamp = currentJournalTimestamp(lhs.timestamp)
        let rhsTimestamp = currentJournalTimestamp(rhs.timestamp)
        switch (lhsTimestamp, rhsTimestamp) {
        case let (.some(lhsTimestamp), .some(rhsTimestamp)) where lhsTimestamp != rhsTimestamp:
            return lhsTimestamp < rhsTimestamp
        case (.none, .some):
            // A current envelope has an explicit intent order. Prefer it when a
            // late join observes it in the same snapshot as a legacy envelope.
            return true
        case (.some, .none):
            return false
        default:
            break
        }

        if lhs.sender.id != rhs.sender.id {
            return lhs.sender.id.uuidString < rhs.sender.id.uuidString
        }
        if lhs.counter != rhs.counter {
            return lhs.counter < rhs.counter
        }
        if lhs.data.effectiveAssetVersion != rhs.data.effectiveAssetVersion {
            return lhs.data.effectiveAssetVersion < rhs.data.effectiveAssetVersion
        }
        return lhsAttachmentId.uuidString < rhsAttachmentId.uuidString
    }

    private static func currentJournalTimestamp(_ timestamp: TimeInterval) -> TimeInterval? {
        guard timestamp.isFinite, timestamp > 0 else { return nil }
        return timestamp
    }

    /// The master only sets `replyToMessageID` on a canonical file presentation
    /// emitted because a particular player presentation could not be accepted as
    /// the baseline. The relationship is stronger than two independent device
    /// clocks and is constrained to the same session item and module.
    private static func isCausalJournalCorrection(
        _ correction: GameNetworkModel,
        replyingTo presentation: GameNetworkModel
    ) -> Bool {
        guard let presentationMessageId = presentation.messageID else { return false }
        return correction.sender.isMaster &&
            correction.replyToMessageID == presentationMessageId &&
            presentation.isPlayerFilePresentationEvent &&
            correction.isFileBackedPresentation &&
            correction.masterId == presentation.masterId &&
            correction.data.type == presentation.data.type &&
            correction.data.id == presentation.data.id
    }

    static func isJournalPresentation(_ metadata: GameNetworkModel) -> Bool {
        (metadata.isFileBackedPresentation || metadata.isPlayerFilePresentationEvent) &&
            !(metadata.data.type == .weather && metadata.targetId != nil)
    }
}

private extension RPGSharePlayController {
    func printState() -> String {
        guard let groupSession else {
            return "Not Active"
        }
        return "\(groupSession.state)"
    }
}

#if os(visionOS)
extension RPGSharePlayController {
    private func configureSystemCoordinator(for session: GroupSession<RPGActivity>) async {
        let sessionId = session.id
        guard !Task.isCancelled,
              sessionLifecycle.isCurrent(sessionId: sessionId),
              groupSession?.id == sessionId
        else { return }
        guard let coordinator = await session.systemCoordinator,
              !Task.isCancelled,
              sessionLifecycle.isCurrent(sessionId: sessionId),
              groupSession?.id == sessionId
        else { return }
        systemCoordinator = coordinator
        applyShareState()
        
        let immersionTask = Task { [weak self] in
            for await immersionStyle in coordinator.groupImmersionStyle {
                guard let self,
                      !Task.isCancelled,
                      self.sessionLifecycle.isCurrent(sessionId: sessionId),
                      self.groupSession?.id == sessionId
                else { return }
                self.gameModel?.shareState.groupImmersionActive = immersionStyle != nil
            }
        }
        tasks[UUID()] = immersionTask
    }
    
    func applyShareState() {
        guard let coordinator = systemCoordinator else { return }
        var configuration = SystemCoordinator.Configuration()
        configuration.supportsGroupImmersiveSpace = true
        switch gameModel?.shareState.mode ?? .window {
        case .tabletop:
            configuration.spatialTemplatePreference = .surround.contentExtent(1)
        case .window, .immersive:
            configuration.spatialTemplatePreference = .sideBySide
        }
        coordinator.configuration = configuration
    }
}

#endif
