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
        participantsWithTable = []
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
        spatialTemplatePreferenceBeforeWindowOverride = nil
        coordinatedTabletopGame = nil
        gameModel?.shareState.isSharePlayActive = false
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
