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
    /// Messenger recovery request. Large modules legitimately take longer to download. A load
    /// that is still suspended at the deadline is not started again (see `loadJournalAttachment`).
    static func journalAttachmentLoadDeadline(for module: NetworkModules) -> Duration {
        switch module {
        case .pdf, .space, .audio: .seconds(180)
        default: .seconds(30)
        }
    }

    /// Longest `loadMetadata` of one attachment may stay suspended. The metadata is small, but
    /// the call is as unbounded as `load`: the snapshots are handled one after the other, so a
    /// call that never returns would keep every later publication from being looked at.
    static let journalMetadataLoadDeadline: Duration = .seconds(20)

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
                let attachmentId = attachment.id
                let metadata = try await SharePlayAttachmentLoadRetry.load(
                    deadline: Self.journalMetadataLoadDeadline,
                    isStillWanted: { [weak self] in
                        await self?.currentJournalAttachmentIds.contains(attachmentId) ?? false
                    },
                    operation: { try await attachment.loadMetadata(of: GameNetworkModel.self) }
                )
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

        let summary = entries.map { "\($0.metadata.counter) \($0.metadata.data.type.token)" }.joined(separator: ", ")
        Logger.sharePlay.debug("Journal: snapshot of \(attachments.count, privacy: .public) attachments: \(summary, privacy: .public)")

        // What this snapshot asks to load, in message order.
        var toLoad: [(attachment: GroupSessionJournal.Attachment, metadata: GameNetworkModel)] = []
        for entry in entries {
            guard !Task.isCancelled,
                  sessionLifecycle.isCurrent(sessionId: sessionId)
            else { return }
            let attachment = entry.attachment
            let metadata = entry.metadata
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
            // The Journal hands every participant every attachment, whoever needs it. A device
            // that already holds the file answered the reference and skips the download.
            if await delegate?.shouldLoadFile(metadata) == false {
                Logger.sharePlay.debug("Journal: skipped attachment \(attachment.id, privacy: .public) of message \(metadata.counter, privacy: .public) (\(metadata.data.type.token, privacy: .public) \(metadata.data.id, privacy: .public)), the file is already here")
                continue
            }
            toLoad.append((attachment, metadata))
        }
        startJournalLoads(toLoad, snapshotCount: attachments.count, sessionId: sessionId)

        guard !Task.isCancelled,
              sessionLifecycle.isCurrent(sessionId: sessionId)
        else { return }
        gameModel?.attachments = currentAttachments
    }

    // MARK: - Concurrent loading

    /// Starts the loads a snapshot asks for without waiting for them, so a slow attachment keeps
    /// neither the next snapshot nor the other attachments from being looked at.
    ///
    /// The first snapshot with something to load (what a late joiner finds in the Journal) keeps
    /// the message order: its loads run one after the other in a task of their own, so the last
    /// presentation the game master showed is the one applied last. Every later snapshot loads
    /// concurrently; only the loads of the same item wait for each other, which keeps a newer
    /// publication of an item behind its older one. A load whose attachment left the Journal
    /// ends on its own.
    private func startJournalLoads(
        _ loads: [(attachment: GroupSessionJournal.Attachment, metadata: GameNetworkModel)],
        snapshotCount: Int,
        sessionId: UUID
    ) {
        guard !loads.isEmpty else { return }
        if !journalJoinBatchHandled {
            journalJoinBatchHandled = true
            let token = UUID()
            let itemIds = Set(loads.map(\.metadata.data.id))
            let previous = itemIds.compactMap { journalLoadTasks[$0]?.task }
            let task = Task { @MainActor [weak self] in
                for task in previous { await task.value }
                for load in loads {
                    guard let self,
                          !Task.isCancelled,
                          self.sessionLifecycle.isCurrent(sessionId: sessionId)
                    else { return }
                    await self.loadJournalAttachment(load.attachment, metadata: load.metadata, snapshotCount: snapshotCount, sessionId: sessionId)
                }
                self?.finishJournalLoad(token: token, itemIds: itemIds)
            }
            for itemId in itemIds {
                journalLoadTasks[itemId] = (token, task)
            }
            return
        }
        for load in loads {
            let itemId = load.metadata.data.id
            let token = UUID()
            let previous = journalLoadTasks[itemId]?.task
            let task = Task { @MainActor [weak self] in
                await previous?.value
                guard let self,
                      !Task.isCancelled,
                      self.sessionLifecycle.isCurrent(sessionId: sessionId)
                else { return }
                await self.loadJournalAttachment(load.attachment, metadata: load.metadata, snapshotCount: snapshotCount, sessionId: sessionId)
                self.finishJournalLoad(token: token, itemIds: [itemId])
            }
            journalLoadTasks[itemId] = (token, task)
        }
    }

    /// Forgets the load `token` for `itemIds`, unless a newer load of the item replaced it.
    private func finishJournalLoad(token: UUID, itemIds: Set<UUID>) {
        for itemId in itemIds where journalLoadTasks[itemId]?.token == token {
            journalLoadTasks[itemId] = nil
        }
    }

    /// Downloads one attachment and hands it to the game, or reports that it did not arrive.
    private func loadJournalAttachment(
        _ attachment: GroupSessionJournal.Attachment,
        metadata initialMetadata: GameNetworkModel,
        snapshotCount: Int,
        sessionId: UUID
    ) async {
        var metadata = initialMetadata
        let attachmentId = attachment.id
        let loadStartedAt = ContinuousClock.now
        let loadLabel = "attachment \(attachmentId) of message \(metadata.counter) (\(metadata.data.type.token) \(metadata.data.id) v\(metadata.data.effectiveAssetVersion))"
        Logger.sharePlay.debug("Journal: loading \(loadLabel, privacy: .public); snapshot held \(snapshotCount, privacy: .public) attachments, session has \(self.groupSession?.activeParticipants.count ?? 0, privacy: .public) participants")
        // A load gives no progress. This says how long it has been waiting and whether the
        // attachment is still in the Journal, until it ends.
        let heartbeat = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled, let self else { return }
                let elapsed = Self.formattedDuration(loadStartedAt.duration(to: .now))
                let stillInJournal = self.currentJournalAttachmentIds.contains(attachmentId)
                Logger.sharePlay.debug("Journal: still loading \(loadLabel, privacy: .public) after \(elapsed, privacy: .public); in the Journal: \(stillInJournal, privacy: .public), Journal holds \(self.currentJournalAttachmentIds.count, privacy: .public) attachments")
            }
        }
        defer { heartbeat.cancel() }
        do {
            let data = try await SharePlayAttachmentLoadRetry.load(
                deadline: Self.journalAttachmentLoadDeadline(for: metadata.data.type),
                isStillWanted: { [weak self] in
                    await self?.currentJournalAttachmentIds.contains(attachmentId) ?? false
                },
                operation: {
                    try await SharePlayAttachmentLoadRetry.load {
                        do {
                            return try await attachment.load(Data.self)
                        } catch {
                            // The retry swallows these: they show what the Journal said.
                            let elapsed = Self.formattedDuration(loadStartedAt.duration(to: .now))
                            Logger.sharePlay.warning("Journal: load of \(loadLabel, privacy: .public) threw after \(elapsed, privacy: .public): \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
                            throw error
                        }
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
                return
            }
            let size = Self.formattedByteCount(data.count)
            let loadDuration = loadStartedAt.duration(to: .now)
            let seconds = max(0.001, Double(loadDuration.components.seconds) + Double(loadDuration.components.attoseconds) / 1e18)
            let rate = Self.formattedByteCount(Int(Double(data.count) / seconds))
            Logger.sharePlay.debug("Journal ✓: received message \(metadata.counter, privacy: .public) attachment \(attachment.id, privacy: .public), size \(size, privacy: .public) in \(Self.formattedDuration(loadDuration), privacy: .public) (\(rate, privacy: .public)/s)")
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
            let elapsed = Self.formattedDuration(loadStartedAt.duration(to: .now))
            Logger.sharePlay.debug("Journal: attachment \(attachment.id, privacy: .public) of message \(metadata.counter, privacy: .public) was replaced while loading (after \(elapsed, privacy: .public)); skipped")
            return
        } catch let error {
            guard !Task.isCancelled,
                  sessionLifecycle.isCurrent(sessionId: sessionId)
            else { return }
            // GroupSessionJournal can publish developer metadata while the
            // CloudAsset still reports `uploadInProgress`. Keep this ID
            // retryable for the next journal snapshot after the short local
            // retry window, and tell the game the bytes did not arrive. A load
            // that stayed suspended until its deadline is not started again: a
            // second one stalled the same way and held up the loads behind it.
            if (error as? SharePlayAttachmentLoadAbort) != .deadlineExceeded {
                journalLedger.retryProcessing(attachmentId: attachment.id)
            }
            let elapsed = Self.formattedDuration(loadStartedAt.duration(to: .now))
            let stillInJournal = currentJournalAttachmentIds.contains(attachment.id)
            Logger.sharePlay.warning("Journal attachment \(attachment.id, privacy: .public) (\(loadLabel, privacy: .public)) remained unavailable after \(elapsed, privacy: .public): \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private); in the Journal: \(stillInJournal, privacy: .public), Journal holds \(self.currentJournalAttachmentIds.count, privacy: .public) attachments, session has \(self.groupSession?.activeParticipants.count ?? 0, privacy: .public) participants")
            guard await performSessionCallback(sessionId: sessionId, operation: {
                await delegate?.handleFileLoadFailure(metadata)
            }) else { return }
        }
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
