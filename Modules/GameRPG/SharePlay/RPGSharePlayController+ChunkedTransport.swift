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
        now: ContinuousClock.Instant = .now
    ) -> SharePlayAssetPublication {
        guard messenger != nil, let sessionId = groupSession?.id else { return .unavailable }
        guard model.carriesAsset, let attachmentData = model.data.data, let journal else {
            return enqueueChunkedSend(model, sessionId: sessionId, participantId: nil) ? .sentByMessenger : .unavailable
        }

        let moduleKey = model.data.type
        let itemId = model.data.id
        let version = model.data.effectiveAssetVersion
        let counter = model.counter
        let attachmentSize = Self.formattedByteCount(attachmentData.count)
        guard journalLedger.shouldUpload(module: moduleKey, itemId: itemId, version: version, counter: counter, now: now) else {
            Logger.sharePlay.debug("Journal: message \(counter, privacy: .public) \(moduleKey.token, privacy: .public) \(itemId, privacy: .public) is already published")
            return .alreadyPublished
        }
        journalLedger.willUpload(module: moduleKey, itemId: itemId, version: version, counter: counter, now: now)

        let metadata = Self.journalMetadata(for: model)
        let publication = journalPublicationQueue.enqueue(
            for: moduleKey,
            byteCount: attachmentData.count,
            policy: Self.journalPublicationPolicy(for: model),
            priority: .userInitiated
        ) { [weak self] in
            guard let self else { return nil }
            guard self.sessionLifecycle.isCurrent(sessionId: sessionId) else { return nil }
            self.recordJournalTransport(state: .pending, byteCount: attachmentData.count, for: model)
            Logger.sharePlay.debug("Journal: message \(counter, privacy: .public) attachment \(attachmentSize, privacy: .public) model: \(model.debugDescription, privacy: .private)")
            let outcome = await self.journalAddLimiter.run(
                for: moduleKey,
                scope: sessionId,
                timeout: Self.journalAddTimeout
            ) {
                try await journal.add(attachmentData, metadata: metadata)
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
                Logger.sharePlay.error("Journal ✕: message \(counter, privacy: .public) cannot add \(attachmentSize, privacy: .public) attachment for module \(moduleKey.token, privacy: .public) and id: \(itemId, privacy: .public) error: \(errorDescription, privacy: .private)")
            case .timedOut:
                Logger.sharePlay.error("Journal ⌛: message \(counter, privacy: .public) timed out adding \(moduleKey.token, privacy: .public) attachment; module is degraded to Messenger until the add returns")
            case .unavailable:
                Logger.sharePlay.warning("Journal bypass: \(moduleKey.token, privacy: .public) still has a quarantined add; using Messenger for message \(counter, privacy: .public)")
            case .cancelled:
                guard self.sessionLifecycle.isCurrent(sessionId: sessionId) else { return nil }
                Logger.sharePlay.warning("Journal add cancelled while session remains active; using Messenger for message \(counter, privacy: .public)")
            }

            guard self.sessionLifecycle.isCurrent(sessionId: sessionId) else { return nil }
            self.journalUploadFailed(model, sessionId: sessionId)
            return nil
        } commit: { [weak self] result in
            guard let self,
                  self.sessionLifecycle.isCurrent(sessionId: sessionId)
            else { return }
            self.gameModel?.attachments[moduleKey] = result
            self.journalLedger.didUpload(
                module: moduleKey,
                itemId: itemId,
                version: version,
                counter: counter,
                attachmentId: result.id
            )
            self.recordJournalTransport(state: .succeeded, byteCount: attachmentData.count, for: model)
            Logger.sharePlay.debug("Journal ✓: message \(counter, privacy: .public) added attachment \(result.id, privacy: .public), size \(attachmentSize, privacy: .public)")
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
            journalUploadFailed(model, sessionId: sessionId)
            return .sentByMessenger
        }
        return .uploading
    }

    /// The Journal did not take the package: frees its ledger slot and sends the same message
    /// through Messenger, which carries smaller packages.
    private func journalUploadFailed(_ model: GameNetworkModel, sessionId: UUID) {
        recordJournalTransport(state: .failed, byteCount: model.data.data?.count ?? 0, for: model)
        journalLedger.uploadFailed(
            module: model.data.type,
            itemId: model.data.id,
            version: model.data.effectiveAssetVersion,
            counter: model.counter
        )
        _ = enqueueChunkedSend(model, sessionId: sessionId, participantId: nil)
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
            Logger.sharePlay.warning("Chunked queue full: ignored message \(model.counter, privacy: .public)")
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
        sessionLifecycle.reset()
        participantTracker.reset()
        journalLedger.reset()
        journalPublicationQueue.cancelAll()
        journalAddLimiter.cancelAll()
        tasks.values.forEach { $0.cancel() }
        tasks = [:]
        participantPlayers = [:]
        packageReceiver.reset()
        inboundByteBudget.reset()
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
