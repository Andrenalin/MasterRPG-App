// @copyright André Trettin

import CoreRPG
import Foundation

// MARK: - Publication policy & admission

enum SharePlayJournalPublicationPolicy: Equatable, Sendable {
    /// Every accepted publication is significant and stays in FIFO order. This
    /// is used for repairs such as Audio/Weather, where dropping one item could
    /// leave a participant without the requested bytes.
    case fifo
    /// Only the newest pending presentation for a module is significant. An
    /// active publication is allowed to finish, while older pending
    /// presentations are replaced before they retain and publish stale bytes.
    case latestWins
}

enum SharePlayJournalPublicationAdmission: Equatable, Sendable {
    case enqueued
    case replacedPending
    case rejected
}

// MARK: - Publication completion bookkeeping

@MainActor
private final class SharePlayJournalPublicationCompletion {
    private var isFinished = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isFinished else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func finish() {
        guard !isFinished else { return }
        isFinished = true
        let currentWaiters = waiters
        waiters = []
        currentWaiters.forEach { $0.resume() }
    }
}

// MARK: - Enqueue result

@MainActor
struct SharePlayJournalPublicationEnqueueResult {
    let admission: SharePlayJournalPublicationAdmission
    private let completion: SharePlayJournalPublicationCompletion

    fileprivate init(
        admission: SharePlayJournalPublicationAdmission,
        completion: SharePlayJournalPublicationCompletion
    ) {
        self.admission = admission
        self.completion = completion
    }

    /// Test/debug synchronization for the accepted publication. Replaced,
    /// rejected, and session-cancelled operations complete immediately.
    var value: Void {
        get async {
            await completion.wait()
        }
    }
}

// MARK: - Publication queue
//
// `retryUntilRemoved` (used by `scheduleCleanup`/`scheduleEmergencyCleanup`
// below) lives in SharePlayDeferredDeliveryQueue.swift alongside
// `SharePlayAttachmentLoadRetry` — see CODE_AUDIT §9.6/§9.10. It's also used
// by `SharePlayJournalAddLimiter.swift`'s `operationFinished(...)`.

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
        maxOutstandingBytes: Int = 512_000_000,
        maxOutstandingCleanups: Int = 8
    ) {
        self.maxOutstandingPublications = max(1, maxOutstandingPublications)
        self.maxOutstandingBytes = max(1, maxOutstandingBytes)
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
    private let maxOutstandingBytes: Int
    private let maxOutstandingCleanups: Int
    private var pendingPublications: [NetworkModules: [PublicationOperation]] = [:]
    private var activePublications: [NetworkModules: PublicationOperation] = [:]
    private var publicationWorkers: [NetworkModules: (id: UUID, task: Task<Void, Never>)] = [:]
    private var cleanupTasks: [UUID: Task<Void, Never>] = [:]
    private var emergencyCleanupTasks: [NetworkModules: Task<Void, Never>] = [:]
    private var currentAttachments: [NetworkModules: Attachment] = [:]
    private var cleanupReservationCount = 0
    private var transferredCleanupReservationOperationIds: Set<UUID> = []
    private var presentationGenerations: [NetworkModules: UInt64] = [:]
    private var generation: UInt = 0
    private(set) var outstandingPublicationCount = 0
    private(set) var outstandingPublicationByteCount = 0

    var outstandingCleanupCount: Int {
        cleanupTasks.count + emergencyCleanupTasks.count
    }

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
              prospectiveByteCount <= maxOutstandingBytes,
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

    func currentAttachment(for module: NetworkModules) -> Attachment? {
        currentAttachments[module]
    }

    /// Marks an active latest-wins add obsolete after a newer presentation has
    /// been safely admitted to Messenger. Rejected fallbacks do not advance the
    /// generation, so the last deliverable presentation is preserved.
    func supersedePresentation(for module: NetworkModules) {
        _ = nextPresentationGeneration(for: module)
    }

    /// Removes the current attachment from the module slot and keeps its
    /// cleanup retained until the system removal finishes. This is used when a
    /// newer presentation falls back to Messenger: a late join must not treat
    /// the older Journal attachment as the current presentation.
    @discardableResult
    func retireCurrentAttachment(
        for module: NetworkModules,
        priority: TaskPriority? = nil,
        remove: @escaping @MainActor (Attachment) async -> Bool
    ) -> Bool {
        guard let attachment = currentAttachments[module] else { return false }

        if let activeOperation = activePublications[module],
           activeOperation.reservesCleanup,
           transferredCleanupReservationOperationIds.insert(activeOperation.id).inserted {
            currentAttachments[module] = nil
            scheduleCleanup(attachment, priority: priority, remove: remove)
            return true
        }

        guard cleanupReservationCount < maxOutstandingCleanups else {
            guard emergencyCleanupTasks[module] == nil else { return false }
            currentAttachments[module] = nil
            scheduleEmergencyCleanup(
                attachment,
                for: module,
                priority: priority,
                remove: remove
            )
            return true
        }

        currentAttachments[module] = nil
        cleanupReservationCount += 1
        scheduleCleanup(attachment, priority: priority, remove: remove)
        return true
    }

    func cancelAll() {
        generation &+= 1
        publicationWorkers.values.forEach { $0.task.cancel() }
        cleanupTasks.values.forEach { $0.cancel() }
        emergencyCleanupTasks.values.forEach { $0.cancel() }
        activePublications.values.forEach { $0.completion.finish() }
        pendingPublications.values.flatMap { $0 }.forEach { $0.completion.finish() }
        pendingPublications = [:]
        activePublications = [:]
        publicationWorkers = [:]
        currentAttachments = [:]
        presentationGenerations = [:]
        // A system removal may ignore cancellation. Keep those task handles and
        // their reservations across sessions so repeated resets cannot create
        // an unbounded set of untracked cleanup operations. Publication-only
        // reservations are released here.
        cleanupReservationCount = cleanupTasks.count
        transferredCleanupReservationOperationIds = []
        outstandingPublicationCount = 0
        outstandingPublicationByteCount = 0
    }

    private func startPublicationWorkerIfNeeded(
        for module: NetworkModules,
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
        for module: NetworkModules,
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

    private func nextPresentationGeneration(for module: NetworkModules) -> UInt64 {
        let nextGeneration = (presentationGenerations[module] ?? 0) &+ 1
        presentationGenerations[module] = nextGeneration
        return nextGeneration
    }

    private func isSupersededPresentation(
        _ operation: PublicationOperation,
        for module: NetworkModules
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
        module: NetworkModules,
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
                remove: { await remove(attachment) },
                finish: { self?.finishCleanup(id: id) }
            )
        }
        cleanupTasks[id] = task
    }

    private func finishCleanup(id: UUID) {
        guard cleanupTasks.removeValue(forKey: id) != nil else { return }
        releaseCleanupReservation()
    }

    /// Fallback retirement must be able to hide the stale current attachment
    /// even when the ordinary cleanup pool is saturated. One extra task per
    /// module keeps that escape hatch finite; the module rejects Journal work
    /// until its retirement returns and uses Messenger in the meantime.
    private func scheduleEmergencyCleanup(
        _ attachment: Attachment,
        for module: NetworkModules,
        priority: TaskPriority?,
        remove: @escaping @MainActor (Attachment) async -> Bool
    ) {
        let task = Task(priority: priority) { [weak self] in
            await retryUntilRemoved(
                delays: SharePlayAttachmentLoadRetry.cleanupRetryDelays,
                remove: { await remove(attachment) },
                finish: { self?.finishEmergencyCleanup(for: module) }
            )
        }
        emergencyCleanupTasks[module] = task
    }

    private func finishEmergencyCleanup(for module: NetworkModules) {
        emergencyCleanupTasks[module] = nil
    }

    /// A publication may ignore cancellation inside the system Journal add and
    /// return an attachment after the queue has reset. It belongs to the old
    /// session and must never become current. Use the queue's single bounded
    /// per-module escape hatch for one best-effort removal so repeated resets
    /// cannot create an untracked retry loop.
    private func scheduleObsoleteCleanup(
        _ attachment: Attachment,
        for module: NetworkModules,
        priority: TaskPriority?,
        remove: @escaping @MainActor (Attachment) async -> Bool
    ) {
        guard emergencyCleanupTasks[module] == nil else { return }
        let task = Task(priority: priority) { @MainActor [weak self] in
            _ = await remove(attachment)
            self?.finishEmergencyCleanup(for: module)
        }
        emergencyCleanupTasks[module] = task
    }

    private func releaseCleanupReservation() {
        cleanupReservationCount = max(0, cleanupReservationCount - 1)
    }

    private func finishPublication(
        _ operation: PublicationOperation,
        module: NetworkModules
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
        for module: NetworkModules,
        workerId: UUID,
        generation operationGeneration: UInt
    ) {
        guard generation == operationGeneration,
              publicationWorkers[module]?.id == workerId
        else { return }
        publicationWorkers[module] = nil
    }
}
