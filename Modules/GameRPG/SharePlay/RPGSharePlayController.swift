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
    func sharePlayLostPlayer(id: UUID)
    /// Called when the local SharePlay session is invalidated so the player
    /// controller can reset `hasSendPlayer` and mark the master as lost.
    func sharePlayLostConnection()
    /// Called each time a session is fully configured and joined. On a player
    /// device this triggers `ready()` so audio availability and the selected
    /// character are re-announced after an automatic re-join.
    func sharePlaySessionConfigured()
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

struct SharePlayJournalTracker: Sendable {
    struct Publication: Equatable, Sendable {
        let attachmentId: UUID
        let itemId: UUID
        let version: Int
    }

    private var processedAttachmentIds: Set<UUID> = []
    private var publications: [NetworkModules: Publication] = [:]

    mutating func reconcile(attachmentIds: Set<UUID>) {
        processedAttachmentIds.formIntersection(attachmentIds)
        publications = publications.filter { attachmentIds.contains($0.value.attachmentId) }
    }

    func shouldPublish(module: NetworkModules, itemId: UUID, version: Int) -> Bool {
        guard let publication = publications[module] else { return true }
        return publication.itemId != itemId || publication.version != version
    }

    mutating func didPublish(module: NetworkModules, itemId: UUID, version: Int, attachmentId: UUID) {
        publications[module] = Publication(attachmentId: attachmentId, itemId: itemId, version: version)
        processedAttachmentIds.insert(attachmentId)
    }

    mutating func didRemove(attachmentId: UUID) {
        processedAttachmentIds.remove(attachmentId)
        publications = publications.filter { $0.value.attachmentId != attachmentId }
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
    }
}

/// Coalesces full photo repairs that are physically broadcast by SharePlay.
/// A `.store/.store` update imports without changing the current presentation,
/// so clearing its target lets one chunk stream satisfy every participant.
struct SharePlayPhotoRepairTracker: Sendable {
    private var sentVersions: [UUID: Int] = [:]

    mutating func prepareMessengerModel(_ model: GameNetworkModel) -> GameNetworkModel? {
        guard model.sender.isMaster,
              model.type == .store,
              model.subType == .store,
              model.data.type == .photo,
              model.data.data != nil,
              model.targetId != nil
        else {
            return model
        }

        guard sentVersions[model.data.id] != model.data.effectiveAssetVersion else { return nil }
        sentVersions[model.data.id] = model.data.effectiveAssetVersion

        var broadcast = model
        broadcast.targetId = nil
        return broadcast
    }

    mutating func reset() {
        sentVersions = [:]
    }
}

@MainActor @Observable
final class RPGSharePlayController {
    var groupSession: GroupSession<RPGActivity>?
    var isActive: Bool = false
    var canActivateSharePlay: Bool = false
    var stateText: String = "Not Active"

    var gameModel: GameRootModel?
    var packageSender: SharePlaySingleQueuePackageSender?
    var packageReceiver = SharePlayPackageReceiver()

    // Kept alive through session resets so the player can re-join automatically
    // when SharePlay becomes available again for a running game. Only cancelled
    // by stopJoin() when the game itself ends.
    private var joinTask: Task<Void, Never>?

    #if os(visionOS)
    private var systemCoordinator: SystemCoordinator?
    #endif

    private let groupStateObserver = GroupStateObserver()

    private var messenger: GroupSessionMessenger?
    private var sessionLifecycle = SharePlaySessionLifecycle()
    private var journalTracker = SharePlayJournalTracker()
    private var photoRepairTracker = SharePlayPhotoRepairTracker()
    // Session-scoped tasks (state/participant/message/journal loops and in-flight
    // sends), cancelled by reset(). Send tasks remove themselves on completion so
    // the collection stays bounded during a long game.
    private var tasks: [UUID: Task<Void, Never>] = [:]
    // Publications for one module are serialized, but cleanup of the previous
    // attachment never blocks publication of the next map/photo/PDF/space.
    private let journalPublicationQueue = SharePlayJournalPublicationQueue<GroupSessionJournal.Attachment>()
    private var journal: GroupSessionJournal?

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

    deinit {
        // Swift 6: deinit is nonisolated and cannot access @MainActor-isolated `tasks`.
        // Cleanup is handled by reset(), which must be called before releasing this controller.
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
        guard let groupSession else { return }
        tabletopGame.coordinateWithSession(groupSession)

        if let gameTableModel = gameTableModel {
            setupSeatAssignment(gameTableModel: gameTableModel)
        }
    }
    #endif
}

extension RPGSharePlayController {
    func sendData(_ gameNetworkModel: GameNetworkModel, fileJournal: Bool) {
        Logger.sharePlay.debug("sendData state: \(self.printState(), privacy: .public) model: \(gameNetworkModel.debugDescription, privacy: .public)")
        guard messenger != nil, let sessionId = groupSession?.id else { return }

        guard let prepared = Self.prepareForTransport(
            gameNetworkModel,
            fileJournal: fileJournal,
            journalAvailable: journal != nil,
            photoRepairTracker: &photoRepairTracker
        ), let encodedModel = prepared.model.encodeData()
        else { return }

        if prepared.usesJournalTransport,
           let attachmentData = prepared.model.data.data, let journal {
            let moduleKey = prepared.model.data.type
            journalPublicationQueue.enqueue(for: moduleKey, priority: .userInitiated) { [weak self] in
                guard let self else { return nil }
                guard self.sessionLifecycle.isCurrent(sessionId: sessionId) else { return nil }
                let attachmentSize = Self.formattedByteCount(attachmentData.count)
                self.recordJournalTransport(
                    state: .pending,
                    byteCount: attachmentData.count,
                    for: prepared.model
                )
                Logger.sharePlay.debug("Journal: message \(prepared.model.counter, privacy: .public) attachment \(attachmentSize, privacy: .public) model: \(prepared.model.debugDescription, privacy: .public)")
                guard self.journalTracker.shouldPublish(
                    module: moduleKey,
                    itemId: prepared.model.data.id,
                    version: prepared.model.data.effectiveAssetVersion
                ) else {
                    self.recordJournalTransport(
                        state: .succeeded,
                        byteCount: attachmentData.count,
                        for: prepared.model
                    )
                    Logger.sharePlay.debug("Journal ✓: message \(prepared.model.counter, privacy: .public) reused \(attachmentSize, privacy: .public) \(moduleKey.token, privacy: .public) attachment for \(prepared.model.data.id, privacy: .public)")
                    return nil
                }
                let model = Self.journalMetadata(for: prepared.model)
                do {
                    let result = try await journal.add(attachmentData, metadata: model)
                    guard self.sessionLifecycle.isCurrent(sessionId: sessionId) else { return nil }
                    self.gameModel?.attachments[prepared.model.data.type] = result
                    self.journalTracker.didPublish(
                        module: moduleKey,
                        itemId: prepared.model.data.id,
                        version: prepared.model.data.effectiveAssetVersion,
                        attachmentId: result.id
                    )
                    self.recordJournalTransport(
                        state: .succeeded,
                        byteCount: attachmentData.count,
                        for: prepared.model
                    )
                    Logger.sharePlay.debug("Journal ✓: message \(prepared.model.counter, privacy: .public) added attachment \(result.id, privacy: .public), size \(attachmentSize, privacy: .public)")
                    return result
                } catch {
                    self.recordJournalTransport(
                        state: .failed,
                        byteCount: attachmentData.count,
                        for: prepared.model
                    )
                    Logger.sharePlay.error("Journal ✕: message \(prepared.model.counter, privacy: .public) cannot add \(attachmentSize, privacy: .public) attachment for module \(prepared.model.data.type.token, privacy: .public) and id: \(prepared.model.data.id, privacy: .public) error: \(error.localizedDescription, privacy: .public)")
                    if self.sessionLifecycle.isCurrent(sessionId: sessionId), let sender = self.packageSender {
                        await self.sendChunked(encodedModel, for: prepared.model, using: sender)
                    }
                    return nil
                }
            } remove: { [weak self] oldAttachment in
                guard let self,
                      self.sessionLifecycle.isCurrent(sessionId: sessionId)
                else { return }
                do {
                    try await journal.remove(attachment: oldAttachment)
                    guard self.sessionLifecycle.isCurrent(sessionId: sessionId) else { return }
                    self.journalTracker.didRemove(attachmentId: oldAttachment.id)
                    Logger.sharePlay.debug("Journal ✓: removed replaced \(moduleKey.token, privacy: .public) attachment \(oldAttachment.id, privacy: .public)")
                } catch is CancellationError {
                    // Session reset cancels cleanup tasks. The next session owns
                    // a different journal, so cancellation needs no recovery.
                } catch {
                    Logger.sharePlay.error("Cannot remove replaced attachment from Journal with module \(moduleKey.token, privacy: .public) error: \(error.localizedDescription, privacy: .public)")
                }
            }
            return
        }

        // Messenger photo repairs are normalized to one untargeted store, so
        // every participant caches the bytes without changing presentation.
        addSendTask { [weak self] in
            guard let self,
                  self.sessionLifecycle.isCurrent(sessionId: sessionId),
                  let sender = self.packageSender
            else { return }
            await self.sendChunked(encodedModel, for: prepared.model, using: sender)
        }
    }

    /// Chooses transport using the original targeted model, then normalizes a
    /// photo repair for messenger delivery. Choosing again after clearing the
    /// target would incorrectly move the repair back onto the journal.
    static func prepareForTransport(
        _ model: GameNetworkModel,
        fileJournal: Bool,
        journalAvailable: Bool,
        photoRepairTracker: inout SharePlayPhotoRepairTracker
    ) -> (model: GameNetworkModel, usesJournalTransport: Bool)? {
        let usesJournal = usesJournalTransport(
            for: model,
            fileJournal: fileJournal,
            journalAvailable: journalAvailable
        )
        guard !usesJournal else { return (model, true) }
        guard let preparedModel = photoRepairTracker.prepareMessengerModel(model) else { return nil }
        return (preparedModel, false)
    }

    /// The journal slot per module carries broadcast content — the master's
    /// current presentation — plus audio, whose targeted repairs are morphed
    /// into untargeted stores. Targeted answers of the other modules ride the
    /// messenger; full photo stores are normalized there into one coalesced
    /// group repair. Neither path can replace (and abort) an attachment that
    /// participants are still downloading.
    static func usesJournalTransport(for model: GameNetworkModel, fileJournal: Bool, journalAvailable: Bool) -> Bool {
        fileJournal && journalAvailable && model.data.data != nil && (model.targetId == nil || model.data.type == .audio)
    }

    static func journalMetadata(for model: GameNetworkModel) -> GameNetworkModel {
        var metadata = model
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

    /// Runs a send operation as a session-scoped task that is cancellable by
    /// reset() but removes itself when finished, so `tasks` stays bounded.
    private func addSendTask(priority: TaskPriority? = nil, _ operation: @escaping @MainActor () async -> Void) {
        let id = UUID()
        tasks[id] = Task(priority: priority) { [weak self] in
            await operation()
            self?.tasks.removeValue(forKey: id)
        }
    }

    /// Registers a session-scoped task that reset() cancels. Passing a stable
    /// key replaces (and cancels) the previous task for that key, so repeated
    /// registrations don't accumulate duplicate observers.
    func trackSessionTask(_ task: Task<Void, Never>, key: UUID = UUID()) {
        tasks[key]?.cancel()
        tasks[key] = task
    }

    private func sendChunked(
        _ data: Data,
        for model: GameNetworkModel,
        using sender: SharePlaySingleQueuePackageSender
    ) async {
        let packageCount = sender.packageCount(for: data)
        let size = Self.formattedByteCount(data.count)
        recordChunkedTransport(count: packageCount, byteCount: data.count, for: model)
        Logger.sharePlay.debug("Chunked: message \(model.counter, privacy: .public), packages \(packageCount, privacy: .public), encoded size \(size, privacy: .public)")
        do {
            try await sender.send(data: data)
            Logger.sharePlay.debug("Chunked ✓: message \(model.counter, privacy: .public), packages \(packageCount, privacy: .public)")
        } catch is CancellationError {
            Logger.sharePlay.debug("Chunked cancelled: message \(model.counter, privacy: .public)")
        } catch {
            // Missing one package leaves the receiver waiting forever. Keep the
            // failure visible after the sender has exhausted its bounded retry.
            Logger.sharePlay.error("Chunked ✕: message \(model.counter, privacy: .public), packages \(packageCount, privacy: .public), error: \(error.localizedDescription, privacy: .public)")
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

    private func recordChunkedTransport(count: Int, byteCount: Int, for model: GameNetworkModel) {
        updateTransportLog(for: model) { transport in
            transport.chunked = SharePlayChunkTransportLog(count: count, byteCount: byteCount)
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
        isActive = false
        messenger = nil
        packageSender = nil
        journal = nil
        sessionLifecycle.reset()
        journalTracker.reset()
        photoRepairTracker.reset()
        journalPublicationQueue.cancelAll()
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
        let activity = RPGActivity(adventureTitle: name ?? "Adventure")
        if let groupSession {
            Logger.sharePlay.debug("GroupSession active state: \(self.printState(), privacy: .public)")
            groupSession.activity = activity
        } else {
            Task {
                do {
                    _ = try await activity.activate()
                    Logger.sharePlay.debug("Activate state: \(self.printState(), privacy: .public)")
                } catch {
                    Logger.sharePlay.error("Activate error \(error.localizedDescription) state: \(self.printState(), privacy: .public)")
                }
            }
        }
    }

    func joinGame() {
        Logger.sharePlay.debug("Join state: \(self.printState(), privacy: .public)")
        joinTask?.cancel()
        // Store in joinTask (not tasks) so reset() does not cancel it.
        // The for-await loop stays alive across session invalidations and picks
        // up the next session automatically when the player re-joins the call.
        joinTask = Task { [weak self] in
            for await session in RPGActivity.sessions() {
                guard let self else { return }
                Logger.sharePlay.debug("Session \(session.description, privacy: .public) state: \(self.printState(), privacy: .public)")

                #if os(visionOS)
                await self.configureSystemCoordinator(for: session)
                #endif
                self.configureGroupSession(session)
            }
        }
    }

    func stopJoin() {
        Logger.sharePlay.debug("SharePlay: stopJoin")
        joinTask?.cancel()
        joinTask = nil
    }

    func configureGroupSession(_ groupSession: GroupSession<RPGActivity>) {
        Logger.sharePlay.debug("Configure Session \(groupSession.description, privacy: .public) state: \(self.printState(), privacy: .public)")

        sessionLifecycle.prepare(sessionId: groupSession.id)
        self.groupSession = groupSession
        let messenger = GroupSessionMessenger(session: groupSession)
        self.messenger = messenger
        // Bind every in-flight package stream to the messenger for this exact
        // session. A later session replacement must not split one UUID stream
        // across two GroupSessionMessenger instances.
        packageSender = SharePlaySingleQueuePackageSender { package in
            try await messenger.send(package)
        }
        let journal = GroupSessionJournal(session: groupSession)
        self.journal = journal

        #if os(visionOS)
        gameModel?.shareState.isSharePlayActive = false
        #endif
        let stateTask = Task { [weak self] in
            for await state in groupSession.$state.values {
                guard let self else { return }
                guard self.sessionLifecycle.isCurrent(sessionId: groupSession.id) else { return }
                let stateDescription = self.printState()
                Logger.sharePlay.debug("Session state: \(stateDescription, privacy: .public)")
                self.stateText = stateDescription
                switch state {
                case .waiting:
                    break
                case .joined:
                    self.isActive = true
                    #if os(visionOS)
                    self.gameModel?.shareState.isSharePlayActive = true
                    #endif
                    if self.sessionLifecycle.didEnterJoinedState(sessionId: groupSession.id) {
                        self.delegate?.sharePlaySessionConfigured()
                    }
                case .invalidated:
                    self.groupSession = nil
                    self.reset()
                    // Notify the player controller so it resets hasSendPlayer
                    // and marks the master as lost — required for re-sync on rejoin.
                    self.delegate?.sharePlayLostConnection()
                    return
                @unknown default:
                    break
                }
            }
        }
        tasks[UUID()] = stateTask

        // Combine's .receive(on:) introduces an async hop that lets the @Published property
        // update before the sink runs — so groupSession.activeParticipants equals activeParticipants
        // by the time the closure fires, making the subtracting() always empty.
        // Apple's recommended approach (WWDC visionOS SharePlay sample) is to use
        // `for await .values` with an explicit previousParticipants local that is updated
        // via defer, which is unambiguous regardless of scheduling.
        let participantTask = Task { [weak self] in
            guard let self else { return }
            var previousParticipants = Set<Participant>()
            for await activeParticipants in groupSession.$activeParticipants.values {
                let removed = previousParticipants.subtracting(activeParticipants)
                let added = activeParticipants.subtracting(previousParticipants)
                defer { previousParticipants = activeParticipants }
                Logger.sharePlay.debug("Session Participants active: \(activeParticipants.debugDescription, privacy: .public) added: \(added.debugDescription, privacy: .public) removed: \(removed.debugDescription, privacy: .public)")
                if !added.isEmpty {
                    // A joining participant may legitimately lack a photo that
                    // was repaired for the previous group membership.
                    self.photoRepairTracker.reset()
                }
                for participant in removed {
                    self.delegate?.sharePlayLostPlayer(id: participant.id)
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
                if let data = self.packageReceiver.received(package: message)?.data {
                    let size = Self.formattedByteCount(data.count)
                    Logger.sharePlay.debug("Chunked ✓: received \(message.total, privacy: .public) packages, assembled size \(size, privacy: .public) from \(context.source.id, privacy: .public)")
                    guard let gameModel = GameNetworkModel.decodeData(of: data) else { continue }
                    guard !Task.isCancelled,
                          self.sessionLifecycle.isCurrent(sessionId: groupSession.id)
                    else { return }
                    await self.delegate?.handleUpdate(gameModel, id: context.source.id)
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
        Task.detached {
            sessionToJoin.join()
        }
        sessionLifecycle.didRequestJoin(sessionId: groupSession.id)
        playBack?.coordinateWithSession(groupSession)
        #if os(visionOS)
        Task {
            await tabletopGame?.coordinateWithSession(groupSession)
        }
        
        if tabletopGame != nil {
            if let gameTableModel = gameModel?.gameTableModel {
                setupSeatAssignment(gameTableModel: gameTableModel)
            } else {
                Logger.sharePlay.debug("GameTableModel not available at session configure time — seats assigned later")
            }
        }
        #endif
    }

    func handle(_ attachments: GroupSessionJournal.Attachments.Element, sessionId: UUID) async {
        guard !Task.isCancelled,
              sessionLifecycle.isCurrent(sessionId: sessionId)
        else { return }
        journalTracker.reconcile(attachmentIds: Set(attachments.map(\.id)))
        var currentAttachments: [NetworkModules: GroupSessionJournal.Attachment] = [:]
        var entries: [(attachment: GroupSessionJournal.Attachment, metadata: GameNetworkModel)] = []

        for attachment in attachments {
            do {
                let metadata = try await attachment.loadMetadata(of: GameNetworkModel.self)
                guard !Task.isCancelled,
                      sessionLifecycle.isCurrent(sessionId: sessionId)
                else { return }
                entries.append((attachment, metadata))
            } catch is CancellationError {
                return
            } catch let error {
                guard !Task.isCancelled,
                      sessionLifecycle.isCurrent(sessionId: sessionId)
                else { return }
                Logger.sharePlay.error("Exception in load attachment metaData \(error.localizedDescription, privacy: .public)")
            }
        }

        // Add-before-remove intentionally creates a short snapshot containing
        // both the old and new map. Process counters oldest-to-newest so a late
        // join or transient overlap cannot finish by presenting the old map.
        entries.sort {
            Self.journalEntryComesBefore(
                metadata: $0.metadata,
                attachmentId: $0.attachment.id,
                metadata: $1.metadata,
                attachmentId: $1.attachment.id
            )
        }
        let latestPresentationAttachmentId = Self.latestJournalPresentationAttachmentId(
            in: entries.map { (attachmentId: $0.attachment.id, metadata: $0.metadata) }
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
                await delegate?.handleFileUpdate(metadata)
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
                await delegate?.handleFileLoadFailure(metadata)
            }
        }

        guard !Task.isCancelled,
              sessionLifecycle.isCurrent(sessionId: sessionId)
        else { return }
        gameModel?.attachments = currentAttachments
    }

    /// Gives transient add-before-remove snapshots a stable processing order.
    /// Message counters are authoritative for successive publications from the
    /// master; version and attachment ID only make malformed/equal-counter
    /// snapshots deterministic.
    static func journalEntryComesBefore(
        metadata lhs: GameNetworkModel,
        attachmentId lhsAttachmentId: UUID,
        metadata rhs: GameNetworkModel,
        attachmentId rhsAttachmentId: UUID
    ) -> Bool {
        if lhs.counter != rhs.counter {
            return lhs.counter < rhs.counter
        }
        if lhs.data.effectiveAssetVersion != rhs.data.effectiveAssetVersion {
            return lhs.data.effectiveAssetVersion < rhs.data.effectiveAssetVersion
        }
        return lhsAttachmentId.uuidString < rhsAttachmentId.uuidString
    }

    static func latestJournalPresentationAttachmentId(
        in entries: [(attachmentId: UUID, metadata: GameNetworkModel)]
    ) -> UUID? {
        var latest: (attachmentId: UUID, metadata: GameNetworkModel)?

        for entry in entries where isJournalPresentation(entry.metadata) {
            guard let current = latest else {
                latest = entry
                continue
            }
            if journalEntryComesBefore(
                metadata: current.metadata,
                attachmentId: current.attachmentId,
                metadata: entry.metadata,
                attachmentId: entry.attachmentId
            ) {
                latest = entry
            }
        }

        return latest?.attachmentId
    }

    static func isJournalPresentation(_ metadata: GameNetworkModel) -> Bool {
        metadata.isFileBackedPresentation
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
        guard let coordinator = await session.systemCoordinator else { return }
        systemCoordinator = coordinator
        applyShareState()
        
        let immersionTask = Task { [weak self] in
            for await immersionStyle in coordinator.groupImmersionStyle {
                guard let self else { return }
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
