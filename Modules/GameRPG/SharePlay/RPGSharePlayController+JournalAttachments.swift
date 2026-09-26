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

extension RPGSharePlayController {

    // MARK: - Journal attachment handling

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

    static func journalMetadataComesBefore(
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

    static func currentJournalTimestamp(_ timestamp: TimeInterval) -> TimeInterval? {
        guard timestamp.isFinite, timestamp > 0 else { return nil }
        return timestamp
    }

    /// The master only sets `replyToMessageID` on a canonical file presentation
    /// emitted because a particular player presentation could not be accepted as
    /// the baseline. The relationship is stronger than two independent device
    /// clocks and is constrained to the same session item and module.
    static func isCausalJournalCorrection(
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
