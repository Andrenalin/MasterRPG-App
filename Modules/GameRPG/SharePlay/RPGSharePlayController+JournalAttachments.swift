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

extension RPGSharePlayController {

    // MARK: - Journal attachment handling

    /// Longest a single attachment load may stay suspended before the player falls back to the
    /// Messenger recovery request. Large modules legitimately take longer to download.
    static func journalAttachmentLoadDeadline(for module: NetworkModules) -> Duration {
        switch module {
        case .pdf, .space, .audio: .seconds(120)
        default: .seconds(30)
        }
    }

    /// Records the newest full Journal snapshot and makes sure one drain task processes it.
    /// Older unprocessed snapshots are dropped: every snapshot lists all current attachments.
    func receiveJournalSnapshot(
        _ snapshot: GroupSessionJournal.Attachments.Element,
        sessionId: UUID
    ) {
        currentJournalAttachmentIds = Set(snapshot.map(\.id))
        pendingJournalSnapshot = snapshot
        guard journalDrainTask == nil else { return }
        let task = Task { @MainActor [weak self] in
            while let self,
                  !Task.isCancelled,
                  self.sessionLifecycle.isCurrent(sessionId: sessionId),
                  let next = self.pendingJournalSnapshot {
                self.pendingJournalSnapshot = nil
                await self.handle(next, sessionId: sessionId)
            }
            // No suspension between the loop's last check and this assignment.
            if let self, self.sessionLifecycle.isCurrent(sessionId: sessionId) {
                self.journalDrainTask = nil
            }
        }
        journalDrainTask = task
        tasks[UUID()] = task
    }

    func handle(_ attachments: GroupSessionJournal.Attachments.Element, sessionId: UUID) async {
        guard !Task.isCancelled,
              sessionLifecycle.isCurrent(sessionId: sessionId)
        else { return }
        journalLedger.reconcile(attachmentIds: Set(attachments.map(\.id)))
        var currentAttachments: [NetworkModules: GroupSessionJournal.Attachment] = [:]
        var entries: [(attachment: GroupSessionJournal.Attachment, metadata: GameNetworkModel)] = []

        let attachmentIds = Set(attachments.map(\.id))
        journalMetadataCache = journalMetadataCache.filter { attachmentIds.contains($0.key) }
        for attachment in attachments {
            if let cached = journalMetadataCache[attachment.id] {
                entries.append((attachment, cached))
                continue
            }
            do {
                let metadata = try await attachment.loadMetadata(of: GameNetworkModel.self)
                guard !Task.isCancelled,
                      sessionLifecycle.isCurrent(sessionId: sessionId)
                else { return }
                journalMetadataCache[attachment.id] = metadata
                entries.append((attachment, metadata))
            } catch is CancellationError {
                return
            } catch let error {
                guard !Task.isCancelled,
                      sessionLifecycle.isCurrent(sessionId: sessionId)
                else { return }
                Logger.sharePlay.error("Exception in load attachment metaData \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
            }
        }

        // A late join observes several publications at once. The message counter orders them,
        // so the player's last presentation is the one the game master showed last.
        entries.sort {
            Self.journalMetadataComesBefore(
                metadata: $0.metadata,
                attachmentId: $0.attachment.id,
                metadata: $1.metadata,
                attachmentId: $1.attachment.id
            )
        }

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
            // A removed/re-added item gets a new attachment ID and is therefore
            // processed again.
            guard journalLedger.shouldProcess(attachmentId: attachment.id) else { continue }
            if metadata.sender.id == gameModel?.gameConfig.id { continue }
            Logger.sharePlay.debug("Attachments \(metadata.counter, privacy: .public)")
            do {
                let attachmentId = attachment.id
                let data = try await SharePlayAttachmentLoadRetry.load(
                    deadline: Self.journalAttachmentLoadDeadline(for: metadata.data.type),
                    isStillWanted: { [weak self] in
                        await self?.currentJournalAttachmentIds.contains(attachmentId) ?? false
                    },
                    operation: {
                        try await SharePlayAttachmentLoadRetry.load {
                            try await attachment.load(Data.self)
                        }
                    }
                )
                guard !Task.isCancelled,
                      sessionLifecycle.isCurrent(sessionId: sessionId)
                else { return }
                // A participant can publish a blob of any size; the Messenger path refuses more
                // than this. See CODE_AUDIT_23 §6.5.
                guard data.count <= GameLimits.maximumMessageBytes else {
                    Logger.sharePlay.warning("Journal: attachment \(attachment.id, privacy: .public) of message \(metadata.counter, privacy: .public) exceeds the size limit; ignored")
                    continue
                }
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
            } catch SharePlayAttachmentLoadAbort.noLongerCurrent {
                // The publisher replaced this attachment while it was loading. The newer
                // snapshot already carries its successor, which is processed next.
                guard !Task.isCancelled,
                      sessionLifecycle.isCurrent(sessionId: sessionId)
                else { return }
                Logger.sharePlay.debug("Journal: attachment \(attachment.id, privacy: .public) of message \(metadata.counter, privacy: .public) was replaced while loading; skipped")
                continue
            } catch let error {
                guard !Task.isCancelled,
                      sessionLifecycle.isCurrent(sessionId: sessionId)
                else { return }
                // GroupSessionJournal can publish developer metadata while the
                // CloudAsset still reports `uploadInProgress`. Keep this ID
                // retryable for the next journal snapshot after the short local
                // retry window, and tell the game the bytes did not arrive.
                journalLedger.retryProcessing(attachmentId: attachment.id)
                Logger.sharePlay.warning("Journal attachment \(attachment.id, privacy: .public) remained unavailable after retries: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
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

    /// Orders the attachments of one snapshot: by the sender's message counter, with the
    /// sender and the attachment id as stable tie-breaks across senders.
    static func journalMetadataComesBefore(
        metadata lhs: GameNetworkModel,
        attachmentId lhsAttachmentId: UUID,
        metadata rhs: GameNetworkModel,
        attachmentId rhsAttachmentId: UUID
    ) -> Bool {
        if lhs.sender.id != rhs.sender.id {
            // The game master's publications are processed last, so its presentation wins.
            if lhs.sender.isMaster != rhs.sender.isMaster {
                return rhs.sender.isMaster
            }
            return lhs.sender.id.uuidString < rhs.sender.id.uuidString
        }
        if lhs.counter != rhs.counter {
            return lhs.counter < rhs.counter
        }
        return lhsAttachmentId.uuidString < rhsAttachmentId.uuidString
    }
}
