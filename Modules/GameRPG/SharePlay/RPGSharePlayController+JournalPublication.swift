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

// The Journal publication of assets, split out of RPGSharePlayController+ChunkedTransport.swift. See CODE_AUDIT_29 §9.9.

extension RPGSharePlayController {
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
        // A large package is not sent a second way when its add times out: Messenger is slower
        // than the upload still running, and the timed-out add would block the slot meanwhile.
        // See CODE_AUDIT_Game_Photo_Audio §7.2.
        let waitsForLateAdd = exceedsMessenger
            || GameLimits.SharePlay.journalWaitsInsteadOfFallback(forByteCount: attachmentData.count)
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
                timeout: Self.journalAddTimeout(forByteCount: attachmentData.count)
            ) {
                try await journal.add(attachmentData, metadata: metadata)
            } discardLateValue: { [weak self] lateAttachment in
                guard let self else { return true }
                if waitsForLateAdd, self.adoptLateJournalAttachment(
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
                if waitsForLateAdd {
                    Logger.sharePlay.warning("Journal: message \(counter, privacy: .public) is \(exceedsMessenger ? "too large for Messenger" : "faster to wait for than to resend", privacy: .public); its late add is kept when it returns")
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

    /// The Journal did not take the package: sends the same message through Messenger, which
    /// carries smaller packages. The ledger keeps the show as delivered then: a request for it
    /// that arrives later finds the slot taken and is not answered with the whole file over
    /// Messenger a second time. The slot is freed only when Messenger cannot carry the message
    /// either, so the next request or show can try again.
    /// See CODE_AUDIT_Game_Photo_Audio §5.3.
    @discardableResult
    private func journalUploadFailed(_ model: GameNetworkModel, show: SharePlayJournalLedger.Show, sessionId: UUID) -> Bool {
        recordJournalTransport(state: .failed, byteCount: model.data.data?.count ?? 0, for: model)
        guard enqueueChunkedSend(model, sessionId: sessionId, participantId: nil) else {
            journalLedger.uploadFailed(show)
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

    func recordJournalTransport(
        state: SharePlayJournalTransportState,
        byteCount: Int,
        for model: GameNetworkModel
    ) {
        updateTransportLog(for: model) { transport in
            transport.journal = SharePlayJournalTransportLog(byteCount: byteCount, state: state)
        }
    }
}
