// @copyright André Trettin

import CoreRPG
import Foundation

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
    private var cleanupTaskOrder: [UUID] = []
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
            guard !Task.isCancelled else {
                self?.finishCleanup(id: id)
                return
            }
            let retryDelays: [Duration] = [
                .milliseconds(250),
                .seconds(1),
                .seconds(2),
                .seconds(5)
            ]
            var retryIndex = 0
            while !Task.isCancelled {
                if await remove(attachment) {
                    guard let self else { return }
                    self.finishCleanup(id: id)
                    return
                }
                do {
                    try await Task.sleep(for: retryDelays[retryIndex])
                } catch {
                    self?.finishCleanup(id: id)
                    return
                }
                retryIndex = min(retryIndex + 1, retryDelays.count - 1)
            }
            self?.finishCleanup(id: id)
        }
        cleanupTasks[id] = task
        cleanupTaskOrder.append(id)
    }

    private func finishCleanup(id: UUID) {
        guard cleanupTasks.removeValue(forKey: id) != nil else { return }
        cleanupTaskOrder.removeAll { $0 == id }
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
            guard !Task.isCancelled else {
                self?.finishEmergencyCleanup(for: module)
                return
            }
            let retryDelays: [Duration] = [
                .milliseconds(250),
                .seconds(1),
                .seconds(2),
                .seconds(5)
            ]
            var retryIndex = 0
            while !Task.isCancelled {
                if await remove(attachment) {
                    self?.finishEmergencyCleanup(for: module)
                    return
                }
                do {
                    try await Task.sleep(for: retryDelays[retryIndex])
                } catch {
                    self?.finishEmergencyCleanup(for: module)
                    return
                }
                retryIndex = min(retryIndex + 1, retryDelays.count - 1)
            }
            self?.finishEmergencyCleanup(for: module)
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

enum SharePlayJournalAddOutcome<Value: Sendable>: Sendable {
    case succeeded(Value)
    case failed(String)
    case timedOut
    case unavailable
    case cancelled
}

@MainActor
private final class SharePlayJournalAddAttempt<Value: Sendable> {
    var continuation: CheckedContinuation<SharePlayJournalAddOutcome<Value>, Never>?
    var operationTask: Task<Void, Never>?
    var timeoutTask: Task<Void, Never>?
    var isWaiting = true
    var isCleaningLateValue = false
    var isObsolete = false
}

private struct SharePlayJournalAddAttemptKey<Key: Hashable & Sendable>: Hashable, Sendable {
    let key: Key
    let scope: UUID?
}

/// Bounds a non-cooperative `GroupSessionJournal.add` to one quarantined task
/// per module. A timeout finishes the logical publication immediately, while
/// the underlying task stays retained and blocks another Journal add for that
/// module until it actually returns. A late attachment is removed instead of
/// being committed as current state.
@MainActor
final class SharePlayJournalAddLimiter<Key: Hashable & Sendable, Value: Sendable> {
    init(maxRetainedAttempts: Int = 16) {
        self.maxRetainedAttempts = max(1, maxRetainedAttempts)
    }

    private let maxRetainedAttempts: Int
    private var attempts: [SharePlayJournalAddAttemptKey<Key>: SharePlayJournalAddAttempt<Value>] = [:]

    var activeCount: Int {
        attempts.count
    }

    func run(
        for key: Key,
        scope: UUID? = nil,
        timeout: Duration,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { duration in
            try await Task.sleep(for: duration)
        },
        lateCleanupSleep: @escaping @Sendable (Duration) async throws -> Void = { duration in
            try await Task.sleep(for: duration)
        },
        operation: @escaping @MainActor () async throws -> Value,
        discardLateValue: @escaping @MainActor (Value) async -> Bool
    ) async -> SharePlayJournalAddOutcome<Value> {
        let attemptKey = SharePlayJournalAddAttemptKey(key: key, scope: scope)
        guard attempts[attemptKey] == nil,
              attempts.count < maxRetainedAttempts
        else { return .unavailable }

        let attempt = SharePlayJournalAddAttempt<Value>()
        attempts[attemptKey] = attempt

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled, attempt.isWaiting else {
                    attempts[attemptKey] = nil
                    continuation.resume(returning: .cancelled)
                    return
                }
                attempt.continuation = continuation
                attempt.operationTask = Task { @MainActor [weak self, weak attempt] in
                    guard let self, let attempt else { return }
                    let result: SharePlayJournalAddOutcome<Value>
                    do {
                        result = .succeeded(try await operation())
                    } catch is CancellationError {
                        result = .cancelled
                    } catch {
                        result = .failed(error.localizedDescription)
                    }
                    await self.operationFinished(
                        result,
                        key: attemptKey,
                        attempt: attempt,
                        lateCleanupSleep: lateCleanupSleep,
                        discardLateValue: discardLateValue
                    )
                }
                attempt.timeoutTask = Task { @MainActor [weak self, weak attempt] in
                    do {
                        try await sleep(timeout)
                    } catch {
                        return
                    }
                    guard let self, let attempt else { return }
                    self.timeout(key: attemptKey, attempt: attempt)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self, weak attempt] in
                guard let self, let attempt else { return }
                self.cancelWaiter(key: attemptKey, attempt: attempt)
            }
        }
    }

    /// Cancels logical waiters on session reset but deliberately retains the
    /// underlying add tasks under `maxRetainedAttempts`. A replacement session
    /// uses a different scope, so one obsolete system call cannot quarantine
    /// that module forever or accumulate untracked orphan work.
    func cancelAll() {
        for (key, attempt) in attempts {
            attempt.isObsolete = true
            if !attempt.isCleaningLateValue {
                attempt.operationTask?.cancel()
            }
            cancelWaiter(key: key, attempt: attempt)
        }
    }

    private func timeout(
        key: SharePlayJournalAddAttemptKey<Key>,
        attempt: SharePlayJournalAddAttempt<Value>
    ) {
        guard attempts[key] === attempt, attempt.isWaiting else { return }
        attempt.isWaiting = false
        attempt.timeoutTask = nil
        attempt.operationTask?.cancel()
        let continuation = attempt.continuation
        attempt.continuation = nil
        continuation?.resume(returning: .timedOut)
    }

    private func cancelWaiter(
        key: SharePlayJournalAddAttemptKey<Key>,
        attempt: SharePlayJournalAddAttempt<Value>
    ) {
        guard attempts[key] === attempt, attempt.isWaiting else { return }
        attempt.isWaiting = false
        attempt.timeoutTask?.cancel()
        attempt.timeoutTask = nil
        attempt.operationTask?.cancel()
        let continuation = attempt.continuation
        attempt.continuation = nil
        continuation?.resume(returning: .cancelled)
    }

    private func operationFinished(
        _ result: SharePlayJournalAddOutcome<Value>,
        key: SharePlayJournalAddAttemptKey<Key>,
        attempt: SharePlayJournalAddAttempt<Value>,
        lateCleanupSleep: @escaping @Sendable (Duration) async throws -> Void,
        discardLateValue: @escaping @MainActor (Value) async -> Bool
    ) async {
        guard attempts[key] === attempt else { return }
        attempt.operationTask = nil

        if attempt.isWaiting {
            attempt.isWaiting = false
            attempt.timeoutTask?.cancel()
            attempt.timeoutTask = nil
            attempts[key] = nil
            let continuation = attempt.continuation
            attempt.continuation = nil
            continuation?.resume(returning: result)
            return
        }

        // The caller already fell back or the session reset. Never install a
        // late attachment as current Journal state.
        if case .succeeded(let value) = result {
            // The add task was cancelled when it timed out. Run cleanup in a
            // fresh unstructured task so inherited cancellation cannot make
            // `journal.remove` fail before it starts. The attempt retains that
            // task, preserving the one-quarantined-operation-per-module bound.
            let cleanupTask = Task { @MainActor in
                let retryDelays: [Duration] = [
                    .milliseconds(250),
                    .seconds(1),
                    .seconds(2),
                    .seconds(5)
                ]
                var retryIndex = 0
                while !Task.isCancelled {
                    if attempt.isObsolete {
                        // The old GroupSession owns this attachment and is
                        // already invalidated. Recheck on every retry because a
                        // reset can occur while removal or its delay is
                        // suspended. One post-reset best-effort call is enough
                        // before releasing the globally bounded attempt slot.
                        _ = await discardLateValue(value)
                        return
                    }
                    if await discardLateValue(value) {
                        return
                    }
                    if attempt.isObsolete {
                        // Reset may have occurred while the removal above was
                        // suspended. Do not retain the global limiter slot for
                        // another backoff cycle; make exactly one post-reset
                        // best-effort call and release the obsolete attempt.
                        _ = await discardLateValue(value)
                        return
                    }
                    do {
                        try await lateCleanupSleep(retryDelays[retryIndex])
                    } catch {
                        return
                    }
                    retryIndex = min(retryIndex + 1, retryDelays.count - 1)
                }
            }
            attempt.isCleaningLateValue = true
            attempt.operationTask = cleanupTask
            await cleanupTask.value
            attempt.operationTask = nil
            attempt.isCleaningLateValue = false
        }
        attempts[key] = nil
    }
}

enum SharePlayMessengerPayloadBudget {
    // GameNetworkModel deliberately uses `.withoutEscapingSlashes`, so Data has
    // only Base64's 4/3 expansion. Reserve one MB for the rest of the model so
    // every admitted raw payload fits the sender's 64 MB complete-message limit
    // without first materializing an undeliverable blob.
    nonisolated static let metadataHeadroom = 1_000_000
    nonisolated static let maximumRawPayloadByteCount =
        ((SharePlaySingleQueuePackageSender.maxMessageByteCount - metadataHeadroom) / 4) * 3
    nonisolated static let maximumOutstandingRawPayloadByteCount = maximumRawPayloadByteCount * 2

    nonisolated static func accepts(rawPayloadByteCount: Int) -> Bool {
        rawPayloadByteCount >= 0 && rawPayloadByteCount <= maximumRawPayloadByteCount
    }
}

enum SharePlayDeferredDeliveryAdmission: Equatable, Sendable {
    case enqueued
    case replaced
    case preservedNewerPresentation
    case enqueuedAfterEvictingPresentations(Int)
    case rejectedTooLarge
    case rejectedSaturated

    var isAccepted: Bool {
        switch self {
        case .enqueued, .replaced, .preservedNewerPresentation,
             .enqueuedAfterEvictingPresentations:
            true
        case .rejectedTooLarge, .rejectedSaturated:
            false
        }
    }
}

struct SharePlayDeferredDeliveryQueue: Sendable {
    struct Entry: Sendable {
        let model: GameNetworkModel
        let sessionId: UUID
        let participantId: UUID?
        let deliveryAttempt: Int
        let retryNotBefore: ContinuousClock.Instant?

        var byteCount: Int {
            model.data.data?.count ?? 0
        }

        func isReady(at instant: ContinuousClock.Instant) -> Bool {
            guard let retryNotBefore else { return true }
            return retryNotBefore <= instant
        }
    }

    private enum Key: Hashable, Sendable {
        case presentation(
            sessionId: UUID,
            participantId: UUID?,
            module: NetworkModules
        )
        case repair(
            sessionId: UUID,
            participantId: UUID?,
            targetId: UUID,
            module: NetworkModules,
            itemId: UUID,
            assetVersion: Int
        )
    }

    init(
        maxCount: Int = 8,
        maxBytes: Int = SharePlayMessengerPayloadBudget.maximumOutstandingRawPayloadByteCount,
        maxEntryBytes: Int = SharePlayMessengerPayloadBudget.maximumRawPayloadByteCount
    ) {
        self.maxCount = max(1, maxCount)
        self.maxBytes = max(1, maxBytes)
        self.maxEntryBytes = max(1, maxEntryBytes)
    }

    private let maxCount: Int
    private let maxBytes: Int
    private let maxEntryBytes: Int
    private var order: [Key] = []
    private var entries: [Key: Entry] = [:]
    private(set) var byteCount = 0

    var count: Int {
        entries.count
    }

    var first: Entry? {
        guard let key = order.first else { return nil }
        return entries[key]
    }

    /// Retains control/presentation intent after both primary transports apply
    /// backpressure. Presentations coalesce to the latest per module and
    /// physical recipient. Targeted Audio/Weather repairs retain an exact
    /// recipient/item/version key. Both count and raw payload bytes are capped.
    @discardableResult
    mutating func enqueue(
        _ model: GameNetworkModel,
        sessionId: UUID,
        participantId: UUID?,
        deliveryAttempt: Int = 0,
        retryNotBefore: ContinuousClock.Instant? = nil
    ) -> SharePlayDeferredDeliveryAdmission {
        guard let key = Self.key(
            for: model,
            sessionId: sessionId,
            participantId: participantId
        ) else { return .rejectedSaturated }

        let newByteCount = model.data.data?.count ?? 0
        guard newByteCount <= maxEntryBytes else { return .rejectedTooLarge }
        let existingEntry = entries[key]

        // A failed send can retry after a newer presentation for the same
        // module/recipient has already been deferred. The retry represents the
        // older intent, so it must not coalesce over the newer entry. Repairs
        // deliberately keep their existing exact-key replacement and priority
        // semantics because they answer an explicit participant request.
        if deliveryAttempt > 0,
           Self.isPresentation(key),
           existingEntry != nil {
            return .preservedNewerPresentation
        }

        let hadExistingEntry = existingEntry != nil
        let existingByteCount = existingEntry?.byteCount ?? 0
        var prospectiveCount = hadExistingEntry ? entries.count : entries.count + 1
        var prospectiveByteCount = byteCount - existingByteCount + newByteCount
        var evictedPresentationKeys: [Key] = []

        // Repairs answer an explicit participant request. Under pressure they
        // may displace coalescible presentation intent, never another repair.
        if Self.isRepair(key) {
            for candidate in order where
                (prospectiveCount > maxCount || prospectiveByteCount > maxBytes) &&
                candidate != key && Self.isPresentation(candidate) {
                guard let evicted = entries[candidate] else { continue }
                evictedPresentationKeys.append(candidate)
                prospectiveCount -= 1
                prospectiveByteCount -= evicted.byteCount
            }
        }

        guard prospectiveCount <= maxCount,
              prospectiveByteCount <= maxBytes
        else { return .rejectedSaturated }

        if entries[key] != nil {
            remove(key)
        }
        for evictedKey in evictedPresentationKeys {
            remove(evictedKey)
        }
        entries[key] = Entry(
            model: model,
            sessionId: sessionId,
            participantId: participantId,
            deliveryAttempt: max(0, deliveryAttempt),
            retryNotBefore: retryNotBefore
        )
        if Self.isRepair(key) {
            let insertionIndex = order.firstIndex(where: Self.isPresentation) ?? order.endIndex
            order.insert(key, at: insertionIndex)
        } else {
            order.append(key)
        }
        byteCount += newByteCount

        if !evictedPresentationKeys.isEmpty {
            return .enqueuedAfterEvictingPresentations(evictedPresentationKeys.count)
        }
        return hadExistingEntry ? .replaced : .enqueued
    }

    mutating func removeFirst() {
        guard !order.isEmpty else { return }
        remove(order[0])
    }

    mutating func reset() {
        order = []
        entries = [:]
        byteCount = 0
    }

    private static func key(
        for model: GameNetworkModel,
        sessionId: UUID,
        participantId: UUID?
    ) -> Key? {
        if let targetId = model.targetId,
           (model.data.type == .audio || model.data.type == .weather) {
            return .repair(
                sessionId: sessionId,
                participantId: participantId,
                targetId: targetId,
                module: model.data.type,
                itemId: model.data.id,
                assetVersion: model.data.effectiveAssetVersion
            )
        }

        guard model.isFileBackedPresentation || model.isPlayerFilePresentationEvent else {
            return nil
        }
        return .presentation(
            sessionId: sessionId,
            participantId: participantId,
            module: model.data.type
        )
    }

    private static func isRepair(_ key: Key) -> Bool {
        if case .repair = key { return true }
        return false
    }

    private static func isPresentation(_ key: Key) -> Bool {
        if case .presentation = key { return true }
        return false
    }

    private mutating func remove(_ key: Key) {
        order.removeAll { $0 == key }
        if let entry = entries.removeValue(forKey: key) {
            byteCount = max(0, byteCount - entry.byteCount)
        }
    }
}

/// Retries the transient window where a journal entry is visible before its
/// CloudAsset upload is downloadable by another participant.
enum SharePlayAttachmentLoadRetry {
    static let defaultRetryDelays: [Duration] = [
        .milliseconds(250),
        .seconds(1),
        .seconds(2)
    ]

    static func load<Value: Sendable>(
        retryDelays: [Duration] = defaultRetryDelays,
        sleep: @Sendable (Duration) async throws -> Void = { delay in
            try await Task.sleep(for: delay)
        },
        operation: @Sendable () async throws -> Value
    ) async throws -> Value {
        for delay in retryDelays {
            try Task.checkCancellation()
            do {
                return try await operation()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try Task.checkCancellation()
                try await sleep(delay)
            }
        }

        try Task.checkCancellation()
        return try await operation()
    }
}
