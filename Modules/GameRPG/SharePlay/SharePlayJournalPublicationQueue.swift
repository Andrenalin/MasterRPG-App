// @copyright André Trettin

import CoreRPG
import Foundation
import os.log

// MARK: - Publication queue
//
// The slot, policy, admission and completion types are in SharePlayJournalPublication.swift.
// `retryUntilRemoved` (used by `scheduleCleanup`/`scheduleEmergencyCleanup` below) lives in
// SharePlayAttachmentLoadRetry.swift; `SharePlayJournalAddLimiter.swift` uses it as well.

/// Serializes publications for one journal slot without putting removal of the
/// previous attachment on the publication's critical path.
///
/// `GroupSessionJournal.remove(attachment:)` can remain suspended while a peer
/// finishes transferring the attachment. Waiting for that removal before adding
/// the replacement prevents every later item in the same module from being sent.
/// This queue commits the replacement first and performs old-attachment cleanup
/// in a separate session-scoped task.
@MainActor
final class SharePlayJournalPublicationQueue<Attachment: Identifiable & Sendable>
where Attachment.ID == UUID {
    init(
        maxOutstandingPublications: Int = 16,
        maxOutstandingBytes: Int = GameLimits.maximumMessageBytes,
        maxOutstandingTotalBytes: Int? = nil,
        maxOutstandingCleanups: Int = 8,
        cleanupDeadline: Duration = .seconds(30)
    ) {
        self.cleanupDeadline = cleanupDeadline
        self.maxOutstandingPublications = max(1, maxOutstandingPublications)
        self.maxOutstandingBytes = max(1, maxOutstandingBytes)
        self.maxOutstandingTotalBytes = max(self.maxOutstandingBytes, maxOutstandingTotalBytes ?? self.maxOutstandingBytes.multipliedReportingOverflow(by: 3).partialValue)
        self.maxOutstandingCleanups = max(1, maxOutstandingCleanups)
    }

    private struct PublicationOperation {
        let id: UUID
        let byteCount: Int
        let policy: SharePlayJournalPublicationPolicy
        let presentationGeneration: UInt64?
        let reservesCleanup: Bool
        let completion: SharePlayJournalPublicationCompletion
        let publish: @MainActor () async -> Attachment?
        let commit: @MainActor (Attachment) -> Void
        let remove: @MainActor (Attachment) async -> Bool
    }

    private let maxOutstandingPublications: Int
    /// The most one slot may hold: a large package of one module must not keep the others off
    /// the Journal. See CODE_AUDIT_Game_Shareplay §5.11.
    private let maxOutstandingBytes: Int
    /// A backstop over all slots, so the packages waiting in memory stay bounded.
    private let maxOutstandingTotalBytes: Int
    private let maxOutstandingCleanups: Int
    /// Longest one system `remove` may stay suspended before the cleanup gives up on it.
    private let cleanupDeadline: Duration
    private var pendingPublications: [SharePlayJournalSlot: [PublicationOperation]] = [:]
    private var activePublications: [SharePlayJournalSlot: PublicationOperation] = [:]
    private var publicationWorkers: [SharePlayJournalSlot: (id: UUID, task: Task<Void, Never>)] = [:]
    private var cleanupTasks: [UUID: Task<Void, Never>] = [:]
    private var emergencyCleanupTasks: [SharePlayJournalSlot: (id: UUID, task: Task<Void, Never>)] = [:]
    /// The one best-effort removal per slot of an add that returned after its session was
    /// reset. It belongs to the old session, so unlike `emergencyCleanupTasks` it never keeps
    /// the slot off the Journal for the session that follows.
    private var obsoleteCleanupTasks: [SharePlayJournalSlot: (id: UUID, task: Task<Void, Never>)] = [:]
    private var currentAttachments: [SharePlayJournalSlot: Attachment] = [:]
    private var cleanupReservationCount = 0
    private var transferredCleanupReservationOperationIds: Set<UUID> = []
    private var presentationGenerations: [SharePlayJournalSlot: UInt64] = [:]
    private var generation: UInt = 0
    private(set) var outstandingPublicationCount = 0
    private(set) var outstandingPublicationByteCount = 0

    var outstandingCleanupCount: Int {
        cleanupTasks.count + emergencyCleanupTasks.count + obsoleteCleanupTasks.count
    }

    @discardableResult
    func enqueue(
        for module: SharePlayJournalSlot,
        byteCount: Int = 0,
        policy: SharePlayJournalPublicationPolicy = .fifo,
        priority: TaskPriority? = nil,
        publish: @escaping @MainActor () async -> Attachment?,
        commit: @escaping @MainActor (Attachment) -> Void = { _ in },
        remove: @escaping @MainActor (Attachment) async -> Bool
    ) -> SharePlayJournalPublicationEnqueueResult {
        let id = UUID()
        let safeByteCount = max(0, byteCount)
        let completion = SharePlayJournalPublicationCompletion()
        guard emergencyCleanupTasks[module] == nil else {
            completion.finish()
            return SharePlayJournalPublicationEnqueueResult(
                admission: .rejected,
                completion: completion
            )
        }
        let existingPending = pendingPublications[module] ?? []
        let replaceableIds: Set<UUID> = if policy == .latestWins {
            Set(existingPending.lazy.filter { $0.policy == .latestWins }.map(\.id))
        } else {
            []
        }
        let replacedOperations = existingPending.filter { replaceableIds.contains($0.id) }
        let reclaimedBytes = replacedOperations.reduce(into: 0) { result, operation in
            result += operation.byteCount
        }
        let prospectivePublicationCount = outstandingPublicationCount - replacedOperations.count + 1
        let prospectiveByteCount = outstandingPublicationByteCount - reclaimedBytes + safeByteCount
        let slotByteCount = existingPending.reduce(activePublications[module]?.byteCount ?? 0) { $0 + $1.byteCount }
        let prospectiveSlotByteCount = slotByteCount - reclaimedBytes + safeByteCount
        let pendingAfterReplacement = existingPending.filter { !replaceableIds.contains($0.id) }
        let reservesCleanup = currentAttachments[module] != nil ||
            activePublications[module] != nil ||
            !pendingAfterReplacement.isEmpty
        let reclaimedCleanupReservations = replacedOperations.lazy.filter {
            $0.reservesCleanup &&
                !self.transferredCleanupReservationOperationIds.contains($0.id)
        }.count
        let prospectiveCleanupReservationCount = cleanupReservationCount -
            reclaimedCleanupReservations +
            (reservesCleanup ? 1 : 0)

        guard prospectivePublicationCount <= maxOutstandingPublications,
              prospectiveSlotByteCount <= maxOutstandingBytes,
              prospectiveByteCount <= maxOutstandingTotalBytes,
              prospectiveCleanupReservationCount <= maxOutstandingCleanups
        else {
            completion.finish()
            return SharePlayJournalPublicationEnqueueResult(
                admission: .rejected,
                completion: completion
            )
        }

        let presentationGeneration: UInt64? = if policy == .latestWins {
            nextPresentationGeneration(for: module)
        } else {
            nil
        }

        if !replaceableIds.isEmpty {
            pendingPublications[module] = existingPending.filter { operation in
                guard replaceableIds.contains(operation.id) else { return true }
                // A transferred reservation is owned by its already-scheduled
                // cleanup now. Forget only the operation marker; unlike an
                // untransferred pending reservation, its count is not reclaimed.
                transferredCleanupReservationOperationIds.remove(operation.id)
                operation.completion.finish()
                return false
            }
            outstandingPublicationCount -= replacedOperations.count
            outstandingPublicationByteCount -= reclaimedBytes
            cleanupReservationCount -= reclaimedCleanupReservations
        }

        let operation = PublicationOperation(
            id: id,
            byteCount: safeByteCount,
            policy: policy,
            presentationGeneration: presentationGeneration,
            reservesCleanup: reservesCleanup,
            completion: completion,
            publish: publish,
            commit: commit,
            remove: remove
        )
        pendingPublications[module, default: []].append(operation)
        outstandingPublicationCount += 1
        outstandingPublicationByteCount += safeByteCount
        if reservesCleanup {
            cleanupReservationCount += 1
        }
        startPublicationWorkerIfNeeded(for: module, priority: priority)
        return SharePlayJournalPublicationEnqueueResult(
            admission: replacedOperations.isEmpty ? .enqueued : .replacedPending,
            completion: completion
        )
    }

#if DEBUG
    /// A test affordance: the production caller always names the slot.
    @discardableResult
    func enqueue(
        for module: NetworkModules,
        byteCount: Int = 0,
        policy: SharePlayJournalPublicationPolicy = .fifo,
        priority: TaskPriority? = nil,
        publish: @escaping @MainActor () async -> Attachment?,
        commit: @escaping @MainActor (Attachment) -> Void = { _ in },
        remove: @escaping @MainActor (Attachment) async -> Bool
    ) -> SharePlayJournalPublicationEnqueueResult {
        enqueue(
            for: SharePlayJournalSlot(module),
            byteCount: byteCount,
            policy: policy,
            priority: priority,
            publish: publish,
            commit: commit,
            remove: remove
        )
    }

    /// A test affordance: the attachment the slot's last accepted publication left behind.
    func currentAttachment(for slot: SharePlayJournalSlot) -> Attachment? {
        currentAttachments[slot]
    }
#endif

    func cancelAll() {
        generation &+= 1
        publicationWorkers.values.forEach { $0.task.cancel() }
        cleanupTasks.values.forEach { $0.cancel() }
        emergencyCleanupTasks.values.forEach { $0.task.cancel() }
        obsoleteCleanupTasks.values.forEach { $0.task.cancel() }
        activePublications.values.forEach { $0.completion.finish() }
        pendingPublications.values.flatMap { $0 }.forEach { $0.completion.finish() }
        pendingPublications = [:]
        activePublications = [:]
        publicationWorkers = [:]
        currentAttachments = [:]
        presentationGenerations = [:]
        // A system removal may ignore cancellation and never return (its session was
        // invalidated mid-call). The cleanup tasks race it against cancellation and a deadline
        // (`removeBounded`), so they end on their own; they are forgotten here so that a call
        // of the ended session cannot hold a reservation, or the module's slot, in the next one.
        // A task that finishes later finds its entry gone and releases nothing.
        // See CODE_AUDIT_Game_Shareplay §3.2.
        cleanupTasks = [:]
        emergencyCleanupTasks = [:]
        obsoleteCleanupTasks = [:]
        cleanupReservationCount = 0
        transferredCleanupReservationOperationIds = []
        outstandingPublicationCount = 0
        outstandingPublicationByteCount = 0
    }

    private func startPublicationWorkerIfNeeded(
        for module: SharePlayJournalSlot,
        priority: TaskPriority?
    ) {
        guard publicationWorkers[module] == nil else { return }
        let workerId = UUID()
        let operationGeneration = generation
        let task = Task(
            name: "SharePlay Journal Publication",
            priority: priority
        ) { @MainActor [weak self] in
            guard let self else { return }
            await self.drainPublications(
                for: module,
                workerId: workerId,
                generation: operationGeneration,
                priority: priority
            )
        }
        publicationWorkers[module] = (workerId, task)
    }

    private func drainPublications(
        for module: SharePlayJournalSlot,
        workerId: UUID,
        generation operationGeneration: UInt,
        priority: TaskPriority?
    ) async {
        while !Task.isCancelled,
              generation == operationGeneration,
              var moduleQueue = pendingPublications[module],
              !moduleQueue.isEmpty {
            let operation = moduleQueue.removeFirst()
            pendingPublications[module] = moduleQueue.isEmpty ? nil : moduleQueue
            activePublications[module] = operation

            let trace = PerformanceTrace.begin(
                "SharePlayJournalPublish",
                source: module.token,
                byteCount: operation.byteCount
            )
            let newAttachment = await operation.publish()
            trace?.end()
            guard !Task.isCancelled,
                  generation == operationGeneration,
                  activePublications[module]?.id == operation.id
            else {
                if let newAttachment {
                    scheduleObsoleteCleanup(
                        newAttachment,
                        for: module,
                        priority: priority,
                        remove: operation.remove
                    )
                }
                finishWorkerIfCurrent(
                    for: module,
                    workerId: workerId,
                    generation: operationGeneration
                )
                return
            }

            if let newAttachment,
               isSupersededPresentation(operation, for: module) {
                scheduleSupersededCleanup(
                    newAttachment,
                    operation: operation,
                    module: module,
                    priority: priority
                )
            } else if let newAttachment {
                let oldAttachment = currentAttachments.updateValue(newAttachment, forKey: module)
                operation.commit(newAttachment)
                if let oldAttachment, oldAttachment.id != newAttachment.id {
                    scheduleCleanup(
                        oldAttachment,
                        priority: priority,
                        remove: operation.remove
                    )
                } else if operation.reservesCleanup,
                          !transferredCleanupReservationOperationIds.contains(operation.id) {
                    releaseCleanupReservation()
                }
            } else if operation.reservesCleanup,
                      !transferredCleanupReservationOperationIds.contains(operation.id) {
                releaseCleanupReservation()
            }
            finishPublication(operation, module: module)
        }

        finishWorkerIfCurrent(
            for: module,
            workerId: workerId,
            generation: operationGeneration
        )
    }

    private func nextPresentationGeneration(for module: SharePlayJournalSlot) -> UInt64 {
        let nextGeneration = (presentationGenerations[module] ?? 0) &+ 1
        presentationGenerations[module] = nextGeneration
        return nextGeneration
    }

    private func isSupersededPresentation(
        _ operation: PublicationOperation,
        for module: SharePlayJournalSlot
    ) -> Bool {
        guard let operationGeneration = operation.presentationGeneration else { return false }
        return presentationGenerations[module] != operationGeneration
    }

    /// An accepted add can finish after a newer presentation has already fallen
    /// back to Messenger. Its attachment must be removed without ever becoming
    /// the queue's current value or running caller commit side effects.
    private func scheduleSupersededCleanup(
        _ attachment: Attachment,
        operation: PublicationOperation,
        module: SharePlayJournalSlot,
        priority: TaskPriority?
    ) {
        if operation.reservesCleanup,
           transferredCleanupReservationOperationIds.insert(operation.id).inserted {
            scheduleCleanup(attachment, priority: priority, remove: operation.remove)
            return
        }

        // A newer accepted latest-wins operation reserved the cleanup needed
        // for the active result it superseded. Transfer that reservation instead
        // of briefly exceeding the configured cleanup bound.
        if let reservedOperation = pendingPublications[module]?.last(where: {
            $0.policy == .latestWins &&
                $0.reservesCleanup &&
                !transferredCleanupReservationOperationIds.contains($0.id)
        }) {
            transferredCleanupReservationOperationIds.insert(reservedOperation.id)
            scheduleCleanup(attachment, priority: priority, remove: operation.remove)
            return
        }

        if cleanupReservationCount < maxOutstandingCleanups {
            cleanupReservationCount += 1
            scheduleCleanup(attachment, priority: priority, remove: operation.remove)
            return
        }

        // Queue-overload fallback can transfer the active operation's ordinary
        // reservation to retirement of the old current attachment. The single
        // per-module emergency slot owns cleanup of the late active result.
        if emergencyCleanupTasks[module] == nil {
            scheduleEmergencyCleanup(
                attachment,
                for: module,
                priority: priority,
                remove: operation.remove
            )
        }
    }

    private func scheduleCleanup(
        _ attachment: Attachment,
        priority: TaskPriority?,
        remove: @escaping @MainActor (Attachment) async -> Bool
    ) {
        let id = UUID()
        let task = Task(priority: priority) { [weak self] in
            await retryUntilRemoved(
                delays: SharePlayAttachmentLoadRetry.cleanupRetryDelays,
                remove: { await self?.removeBounded(attachment, remove: remove) ?? true },
                finish: { self?.finishCleanup(id: id) }
            )
        }
        cleanupTasks[id] = task
    }

    private func finishCleanup(id: UUID) {
        guard cleanupTasks.removeValue(forKey: id) != nil else { return }
        releaseCleanupReservation()
    }

    /// One system removal, given up on after `cleanupDeadline`. `GroupSessionJournal.remove` can
    /// stay suspended for ever and ignores cancellation, so the removal runs in a task of its
    /// own that is abandoned on the deadline or on cancellation. Returns `true` when the
    /// removal is done *or given up*, which ends the retry loop and frees its slot: a call that
    /// hung once is not worth issuing again. `false` is a removal that failed and may be retried.
    private func removeBounded(
        _ attachment: Attachment,
        remove: @escaping @MainActor (Attachment) async -> Bool
    ) async -> Bool {
        do {
            return try await SharePlayAttachmentLoadRetry.load(deadline: cleanupDeadline) {
                await remove(attachment)
            }
        } catch is CancellationError {
            return false
        } catch {
            Logger.sharePlay.error("Journal: gave up a removal of attachment \(attachment.id, privacy: .public) that did not return within \(String(describing: self.cleanupDeadline), privacy: .public)")
            return true
        }
    }

    /// Fallback retirement must be able to hide the stale current attachment
    /// even when the ordinary cleanup pool is saturated. One extra task per
    /// module keeps that escape hatch finite; the module rejects Journal work
    /// until its retirement returns (or is given up) and uses Messenger in the meantime.
    private func scheduleEmergencyCleanup(
        _ attachment: Attachment,
        for module: SharePlayJournalSlot,
        priority: TaskPriority?,
        remove: @escaping @MainActor (Attachment) async -> Bool
    ) {
        let id = UUID()
        let task = Task(priority: priority) { [weak self] in
            await retryUntilRemoved(
                delays: SharePlayAttachmentLoadRetry.cleanupRetryDelays,
                remove: { await self?.removeBounded(attachment, remove: remove) ?? true },
                finish: { self?.finishEmergencyCleanup(for: module, id: id) }
            )
        }
        emergencyCleanupTasks[module] = (id, task)
    }

    private func finishEmergencyCleanup(for module: SharePlayJournalSlot, id: UUID) {
        guard emergencyCleanupTasks[module]?.id == id else { return }
        emergencyCleanupTasks[module] = nil
    }

    /// A publication may ignore cancellation inside the system Journal add and
    /// return an attachment after the queue has reset. It belongs to the old
    /// session and must never become current. One best-effort removal per slot,
    /// bounded by the deadline, so repeated resets cannot create an untracked retry
    /// loop. It does not occupy the slot's emergency cleanup: the new session may
    /// use the Journal at once.
    private func scheduleObsoleteCleanup(
        _ attachment: Attachment,
        for module: SharePlayJournalSlot,
        priority: TaskPriority?,
        remove: @escaping @MainActor (Attachment) async -> Bool
    ) {
        guard obsoleteCleanupTasks[module] == nil else { return }
        let id = UUID()
        let task = Task(priority: priority) { @MainActor [weak self] in
            _ = await self?.removeBounded(attachment, remove: remove)
            self?.finishObsoleteCleanup(for: module, id: id)
        }
        obsoleteCleanupTasks[module] = (id, task)
    }

    private func finishObsoleteCleanup(for module: SharePlayJournalSlot, id: UUID) {
        guard obsoleteCleanupTasks[module]?.id == id else { return }
        obsoleteCleanupTasks[module] = nil
    }

    private func releaseCleanupReservation() {
        cleanupReservationCount = max(0, cleanupReservationCount - 1)
    }

    private func finishPublication(
        _ operation: PublicationOperation,
        module: SharePlayJournalSlot
    ) {
        guard activePublications[module]?.id == operation.id else { return }
        activePublications[module] = nil
        transferredCleanupReservationOperationIds.remove(operation.id)
        outstandingPublicationCount = max(0, outstandingPublicationCount - 1)
        outstandingPublicationByteCount = max(
            0,
            outstandingPublicationByteCount - operation.byteCount
        )
        operation.completion.finish()
    }

    private func finishWorkerIfCurrent(
        for module: SharePlayJournalSlot,
        workerId: UUID,
        generation operationGeneration: UInt
    ) {
        guard generation == operationGeneration,
              publicationWorkers[module]?.id == workerId
        else { return }
        publicationWorkers[module] = nil
    }
}
