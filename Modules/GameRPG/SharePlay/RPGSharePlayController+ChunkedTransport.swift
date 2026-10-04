// @copyright André Trettin

import AudioRPG
import AVFoundation
import CoreRPG
import Foundation
import GroupActivities
import os.log
import SwiftUI

#if os(visionOS)
import TabletopKit
#endif

// MARK: - Send / chunked transport

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
    func removeJournalAttachment(
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
    func enqueueChunkedSend(
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
    func addSendTask(
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

    func startSendOperationTaskIfNeeded() {
        guard sendOperationTask == nil else { return }
        let generation = sendOperationGeneration
        sendOperationTask = Task { @MainActor [weak self] in
            await self?.drainSendOperations(generation: generation)
        }
    }

    func drainSendOperations(generation: UInt64) async {
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

    func promoteDeferredDeliveries() {
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
            ) else {
                // Symmetry with the "not ready yet" branch above: if
                // capacity is still exhausted right now, schedule a timed
                // re-check as defense in depth instead of relying solely on
                // the next unrelated send's completion to trigger another
                // promotion attempt. A no-op when the head entry has no
                // `retryNotBefore` (nothing to schedule against). See
                // CODE_AUDIT_Network §5.3.
                scheduleDeferredPromotionIfNeeded()
                return
            }
            deferredDeliveryQueue.removeFirst()
        }
    }

    func scheduleDeferredPromotionIfNeeded() {
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
    static func encodedData(for model: GameNetworkModel) async -> Data? {
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
    func sendChunked(
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

    func recordJournalTransport(
        state: SharePlayJournalTransportState,
        byteCount: Int,
        for model: GameNetworkModel
    ) {
        updateTransportLog(for: model) { transport in
            transport.journal = SharePlayJournalTransportLog(byteCount: byteCount, state: state)
        }
    }

    func recordChunkedTransport(
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

    func updateTransportLog(
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

    nonisolated static func formattedByteCount(_ byteCount: Int) -> String {
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
        participantPlayers = [:]
        packageReceiver.reset()
        gameModel?.attachments = [:]
        if groupSession != nil {
            groupSession?.leave()
            groupSession = nil
        }
        #if os(visionOS)
        tabletopGame?.detachNetworkCoordinator()
        systemCoordinator = nil
        coordinatedTabletopGame = nil
        gameModel?.shareState.isSharePlayActive = false
        gameModel?.shareState.groupImmersionActive = false
        #endif
    }
}
