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
    /// `sendData` for callers that have nothing to do with its result: a message the session
    /// neither sent nor kept for a retry is at least logged as lost. Without a session there
    /// is nothing to report. See CODE_AUDIT_21 §5.6.
    func sendDataReportingLoss(
        _ gameNetworkModel: GameNetworkModel,
        participantId: UUID? = nil
    ) {
        let accepted = sendData(gameNetworkModel, participantId: participantId)
        guard !accepted, messenger != nil, groupSession != nil else { return }
        Logger.sharePlay.error("SharePlay did not accept message \(gameNetworkModel.counter, privacy: .public) (\(gameNetworkModel.type.debugDescription, privacy: .public) - \(gameNetworkModel.subType.debugDescription, privacy: .public), \(gameNetworkModel.data.type.token, privacy: .public)): it is lost for SharePlay participants")
    }

    /// Sends a message through Messenger: to the whole session, or physically addressed to one
    /// active participant. Returns whether the transport or its bounded deferred queue accepted
    /// it.
    @discardableResult
    func sendData(
        _ gameNetworkModel: GameNetworkModel,
        participantId: UUID? = nil
    ) -> Bool {
        Logger.sharePlay.debug("sendData state: \(self.printState(), privacy: .public) model: \(gameNetworkModel.debugDescription, privacy: .private)")
        guard messenger != nil, let sessionId = groupSession?.id else { return false }
        return enqueueChunkedSend(gameNetworkModel, sessionId: sessionId, participantId: participantId)
    }

    /// Uploads the package of a file-backed module to the Journal, where every participant
    /// loads it. `SharePlayJournalLedger` decides whether the upload is needed; a package the
    /// Journal cannot take goes through Messenger instead.
    @discardableResult
    func publishAsset(
        _ model: GameNetworkModel,
        isPlaylist: Bool = false,
        now: ContinuousClock.Instant = .now
    ) -> SharePlayAssetPublication {
        guard messenger != nil, let sessionId = groupSession?.id else { return .unavailable }
        guard model.carriesAsset, let attachmentData = model.data.data, let journal else {
            return enqueueChunkedSend(model, sessionId: sessionId, participantId: nil) ? .sentByMessenger : .unavailable
        }

        // The Journal takes no attachment over 100 MB; a larger one would only fail or hang the
        // add. See CODE_AUDIT_Game_Shareplay §6.2.
        guard GameLimits.fitsJournalAttachment(byteCount: attachmentData.count) else {
            Logger.sharePlay.error("Journal: message \(model.counter, privacy: .public) \(model.data.type.token, privacy: .public) \(model.data.id, privacy: .public) is \(attachmentData.count, privacy: .public) bytes, over the Journal limit; not published")
            return .unavailable
        }

        let moduleKey = model.data.type
        let show = SharePlayJournalLedger.Show(model: model, isPlaylist: isPlaylist)
        let slot = show.slot
        let itemId = show.itemId
        let version = show.version
        let counter = show.counter
        let attachmentSize = Self.formattedByteCount(attachmentData.count)
        guard journalLedger.shouldUpload(show, now: now) else {
            Logger.sharePlay.debug("Journal: message \(counter, privacy: .public) \(moduleKey.token, privacy: .public) \(itemId, privacy: .public) is already published")
            return .alreadyPublished
        }
        journalLedger.willUpload(show, now: now)

        let metadata = Self.journalMetadata(for: model)
        // A package Messenger cannot carry has no fallback: a timed-out add of it is awaited,
        // and kept when it returns, instead of being removed and lost.
        // See CODE_AUDIT_Game_Shareplay §5.11.
        let exceedsMessenger = !SharePlayMessengerPayloadBudget.accepts(rawPayloadByteCount: attachmentData.count)
        let enqueuedAt = ContinuousClock.now
        Logger.sharePlay.debug("Journal: message \(counter, privacy: .public) queued \(slot.token, privacy: .public) \(itemId, privacy: .public) v\(version, privacy: .public), \(attachmentSize, privacy: .public), participants \(self.groupSession?.activeParticipants.count ?? 0, privacy: .public)")
        let publication = journalPublicationQueue.enqueue(
            for: slot,
            byteCount: attachmentData.count,
            policy: Self.journalPublicationPolicy(for: model),
            priority: .userInitiated
        ) { [weak self] in
            guard let self else { return nil }
            guard self.sessionLifecycle.isCurrent(sessionId: sessionId) else { return nil }
            self.recordJournalTransport(state: .pending, byteCount: attachmentData.count, for: model)
            let addStartedAt = ContinuousClock.now
            let queueWait = Self.formattedDuration(enqueuedAt.duration(to: addStartedAt))
            Logger.sharePlay.debug("Journal: message \(counter, privacy: .public) attachment \(attachmentSize, privacy: .public), waited \(queueWait, privacy: .public) in the queue, adding now. model: \(model.debugDescription, privacy: .private)")
            let outcome = await self.journalAddLimiter.run(
                for: slot,
                scope: sessionId,
                timeout: Self.journalAddTimeout
            ) {
                try await journal.add(attachmentData, metadata: metadata)
            } discardLateValue: { [weak self] lateAttachment in
                guard let self else { return true }
                if exceedsMessenger, self.adoptLateJournalAttachment(
                    lateAttachment,
                    show: show,
                    sessionId: sessionId
                ) {
                    return true
                }
                return await self.removeJournalAttachment(
                    lateAttachment,
                    from: journal,
                    module: moduleKey,
                    sessionId: sessionId,
                    reason: "late timed-out"
                )
            }

            let addDuration = Self.formattedDuration(addStartedAt.duration(to: .now))
            switch outcome {
            case .succeeded(let result):
                Logger.sharePlay.debug("Journal: message \(counter, privacy: .public) add of \(attachmentSize, privacy: .public) returned attachment \(result.id, privacy: .public) after \(addDuration, privacy: .public), participants \(self.groupSession?.activeParticipants.count ?? 0, privacy: .public)")
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
                Logger.sharePlay.error("Journal ✕: message \(counter, privacy: .public) cannot add \(attachmentSize, privacy: .public) attachment for module \(moduleKey.token, privacy: .public) and id: \(itemId, privacy: .public) after \(addDuration, privacy: .public), error: \(errorDescription, privacy: .private)")
            case .timedOut:
                Logger.sharePlay.error("Journal ⌛: message \(counter, privacy: .public) timed out adding \(moduleKey.token, privacy: .public) attachment after \(addDuration, privacy: .public); module is degraded to Messenger until the add returns")
                if exceedsMessenger {
                    Logger.sharePlay.warning("Journal: message \(counter, privacy: .public) is too large for Messenger; its late add is kept when it returns")
                    return nil
                }
            case .unavailable:
                Logger.sharePlay.warning("Journal bypass: \(moduleKey.token, privacy: .public) still has a quarantined add; using Messenger for message \(counter, privacy: .public)")
            case .cancelled:
                guard self.sessionLifecycle.isCurrent(sessionId: sessionId) else { return nil }
                Logger.sharePlay.warning("Journal add cancelled while session remains active; using Messenger for message \(counter, privacy: .public)")
            }

            guard self.sessionLifecycle.isCurrent(sessionId: sessionId) else { return nil }
            self.journalUploadFailed(model, show: show, sessionId: sessionId)
            return nil
        } commit: { [weak self] result in
            guard let self,
                  self.sessionLifecycle.isCurrent(sessionId: sessionId)
            else { return }
            self.gameModel?.attachments[moduleKey] = result
            self.journalLedger.didUpload(show, attachmentId: result.id)
            self.recordJournalTransport(state: .succeeded, byteCount: attachmentData.count, for: model)
            let total = Self.formattedDuration(enqueuedAt.duration(to: .now))
            Logger.sharePlay.debug("Journal ✓: message \(counter, privacy: .public) added attachment \(result.id, privacy: .public), size \(attachmentSize, privacy: .public), \(slot.token, privacy: .public) \(itemId, privacy: .public), \(total, privacy: .public) since queued")
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
            Logger.sharePlay.warning("Journal queue full: falling back to chunked transport for message \(counter, privacy: .public)")
            return journalUploadFailed(model, show: show, sessionId: sessionId) ? .sentByMessenger : .unavailable
        }
        return .uploading
    }

    /// The Journal did not take the package: frees its ledger slot and sends the same message
    /// through Messenger, which carries smaller packages.
    @discardableResult
    private func journalUploadFailed(_ model: GameNetworkModel, show: SharePlayJournalLedger.Show, sessionId: UUID) -> Bool {
        recordJournalTransport(state: .failed, byteCount: model.data.data?.count ?? 0, for: model)
        journalLedger.uploadFailed(show)
        guard enqueueChunkedSend(model, sessionId: sessionId, participantId: nil) else {
            Logger.sharePlay.error("SharePlay lost message \(model.counter, privacy: .public) (\(model.data.type.token, privacy: .public)): the Journal did not take it and Messenger cannot carry it")
            return false
        }
        return true
    }

    /// Keeps an add that returned after its timeout when Messenger cannot carry the package, as
    /// long as it still is the publication the ledger waits for. Returns whether it was kept.
    private func adoptLateJournalAttachment(
        _ attachment: GroupSessionJournal.Attachment,
        show: SharePlayJournalLedger.Show,
        sessionId: UUID
    ) -> Bool {
        guard sessionLifecycle.isCurrent(sessionId: sessionId),
              let publication = journalLedger.publication(in: show.slot),
              publication.attachmentId == nil,
              publication.itemId == show.itemId,
              publication.version == show.version,
              publication.counter == show.counter
        else { return false }
        gameModel?.attachments[show.slot.module] = attachment
        journalLedger.didUpload(show, attachmentId: attachment.id)
        Logger.sharePlay.debug("Journal ✓: kept the late attachment \(attachment.id, privacy: .public) of message \(show.counter, privacy: .public)")
        return true
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
                journalLedger.didRemove(attachmentId: attachment.id)
            }
            Logger.sharePlay.debug("Journal ✓: removed \(reason, privacy: .public) \(module.token, privacy: .public) attachment \(attachment.id, privacy: .public)")
            return true
        } catch is CancellationError {
            // Session reset cancels normal cleanup. A timed-out add is retained
            // by the limiter and performs late cleanup in a fresh task.
            return false
        } catch {
            Logger.sharePlay.error("Cannot remove \(reason, privacy: .public) Journal attachment for module \(module.token, privacy: .public) after bounded retries: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
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
        if deliveryAttempt == 0, allowDeferral {
            stateSupersession.noteSent(model, participantId: participantId)
        }
        guard SharePlayMessengerPayloadBudget.accepts(
            rawPayloadByteCount: rawPayloadByteCount
        ) else {
            recordChunkedTransport(
                count: 0,
                byteCount: rawPayloadByteCount,
                state: .failed,
                for: model
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
                Logger.sharePlay.error("Chunked ✕: message \(model.counter, privacy: .public) (\(model.data.type.token, privacy: .public)) could not be encoded")
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
            guard outcome == .retryableFailure,
                  deliveryAttempt + 1 < Self.maxChunkedDeliveryAttempts
            else { return }
            // A newer update of the same entity went out meanwhile: resending this one would
            // apply it after the newer one. See CODE_AUDIT_Game_Shareplay §5.18.
            guard !self.stateSupersession.isSuperseded(model, participantId: participantId) else {
                Logger.sharePlay.debug("Chunked retry skipped: message \(model.counter, privacy: .public) was superseded by a newer update")
                return
            }

            let retryAt = ContinuousClock().now.advanced(by: Self.chunkedRetryDelay(forAttempt: deliveryAttempt + 1))
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
            // A promotion that finds the queue still full is not a loss: the entry stays where
            // it is. Only a message that really goes unsent is worth a warning. See
            // CODE_AUDIT_Game_Shareplay §5.2.
            if allowDeferral {
                Logger.sharePlay.warning("Chunked queue full: ignored message \(model.counter, privacy: .public)")
            }
        }
        return enqueued
    }

    /// Reveals represent screen intent: once one waits behind an active publication, a newer
    /// reveal of the same module makes it stale. Stores remain FIFO because each may satisfy a
    /// different request.
    static func journalPublicationPolicy(
        for model: GameNetworkModel
    ) -> SharePlayJournalPublicationPolicy {
        model.type == .reveal ? .latestWins : .fifo
    }

    /// The developer metadata of a Journal attachment: the message without its bytes.
    static func journalMetadata(for model: GameNetworkModel) -> GameNetworkModel {
        var metadata = model
        metadata.data = model.data.reference
        return metadata
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

    /// Sends the deferred messages that are ready, in queue order. Called after every completed
    /// send operation, when a timer for a retry back-off fires and when an entry is deferred.
    ///
    /// A full send queue ends the pass without a timer: a send operation is running, and its
    /// completion calls this again. A timer against a deadline that has already passed fired at
    /// once, promoted, found the queue full and armed the next one, a loop on the main actor for
    /// as long as a large transfer filled the queue (CODE_AUDIT_Game_Shareplay §5.2). A timer is
    /// armed only for the earliest entry that is not ready yet, and an entry that waits for its
    /// back-off no longer holds back the ready ones behind it (§5.17).
    func promoteDeferredDeliveries() {
        deferredDeliveryQueue.removeEntries { [sessionLifecycle] entry in
            !sessionLifecycle.isCurrent(sessionId: entry.sessionId)
        }
        let now = ContinuousClock().now
        while let ready = deferredDeliveryQueue.firstReady(at: now) {
            let delivery = ready.entry
            guard enqueueChunkedSend(
                delivery.model,
                sessionId: delivery.sessionId,
                participantId: delivery.participantId,
                allowDeferral: false,
                deliveryAttempt: delivery.deliveryAttempt
            ) else { return }
            deferredDeliveryQueue.remove(ready.token)
        }
        scheduleDeferredPromotionIfNeeded()
    }

    /// Arms the timer for the earliest deferred entry whose back-off has not passed yet.
    func scheduleDeferredPromotionIfNeeded() {
        let now = ContinuousClock().now
        guard deferredPromotionTask == nil,
              let retryNotBefore = deferredDeliveryQueue.earliestRetry(after: now)
        else { return }
        let generation = sendOperationGeneration
        let delay = now.duration(to: retryNotBefore)
        deferredPromotionTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: delay)
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
        let data = package.takeReassembledData()
        guard !Task.isCancelled,
              let model = GameNetworkModel.decodeData(of: data)
        else { return nil }
        return (model, data.count)
    }

    /// Whether a reassembled package is decoded: not once its sender is over the per-minute
    /// byte budget. See `SharePlayInboundByteBudget`, CODE_AUDIT_21 §6.5.
    func admitsInboundPackage(_ package: SharePlayCompletedPackage, from participantId: UUID) -> Bool {
        guard inboundByteBudget.admit(package.byteCount, from: participantId) else {
            Logger.sharePlay.error("Dropped a \(package.byteCount, privacy: .public) byte package from \(participantId, privacy: .public): over the inbound byte budget")
            return false
        }
        return true
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
        } catch SharePlayPackageDeliveryError.participantNotActive(let participantId) {
            // The addressee left: no retry of this message can reach it, and each one would
            // encode the whole payload again. See CODE_AUDIT_Game_Shareplay §5.16.
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
            Logger.sharePlay.warning("Chunked ✕: message \(model.counter, privacy: .public) is for participant \(participantId, privacy: .private), who is no longer active; not retried")
            return .terminalFailure
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
            Logger.sharePlay.error("Chunked ✕: message \(model.counter, privacy: .public), packages \(packageCount, privacy: .public), error: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
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

    /// Seconds with one decimal, for the transfer logs.
    nonisolated static func formattedDuration(_ duration: Duration) -> String {
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        return seconds.formatted(.number.precision(.fractionLength(1))) + " s"
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
        pendingJournalSnapshot = nil
        currentJournalAttachmentIds = []
        journalDrainTask = nil
        journalLoadSequencer.cancelAll()
        sessionLifecycle.reset()
        participantTracker.reset()
        journalLedger.reset()
        journalPublicationQueue.cancelAll()
        journalAddLimiter.cancelAll()
        stateSupersession.reset()
        tasks.values.forEach { $0.cancel() }
        tasks = [:]
        participantPlayers = [:]
        packageReceiver.reset()
        inboundByteBudget.reset()
        journalLoadBudget.reset()
        gameModel?.attachments = [:]
        if groupSession != nil {
            leaveGroupSession()
            groupSession = nil
        }
        sessionCommands = nil
        #if os(visionOS)
        tabletopGame?.detachNetworkCoordinator()
        systemCoordinator = nil
        coordinatedTabletopGame = nil
        gameModel?.shareState.isSharePlayActive = false
        gameModel?.shareState.groupImmersionActive = false
        #endif
    }

    /// Leaves the current session after a join that is still running. See `GroupSessionCommandQueue`.
    func leaveGroupSession() {
        if let sessionCommands {
            sessionCommands.leave()
        } else {
            groupSession?.leave()
        }
    }
}

extension SharePlayJournalLedger.Show {
    /// The show a message delivers. An audio playlist has its own slot: its first track is
    /// shown right after it.
    init(model: GameNetworkModel, isPlaylist: Bool) {
        self.init(
            slot: SharePlayJournalSlot(model.data.type, isPlaylist: isPlaylist && model.data.type == .audio),
            itemId: model.data.id,
            version: model.data.effectiveAssetVersion,
            counter: model.counter
        )
    }
}
