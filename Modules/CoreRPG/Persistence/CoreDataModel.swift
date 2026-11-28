// @copyright André Trettin

import CoreData
import os.log
import SwiftUI
import Synchronization

// The store model and pending operations, split out of CoreDataController.swift. See CODE_AUDIT_29 §9.9.

/// Mutex-backed (not an actor) so enqueuing is synchronous: operations arrive in
/// call order and are always visible to the next `flushPendingOperations`. An
/// unstructured Task per enqueue could reorder rapid edits to the same id or miss
/// a save that races the enqueue.
final class CoreDataModel: Sendable {
    /// How often a rollback may re-queue the same operation before it is discarded. A save
    /// error that keeps recurring (disk full, one invalid object) would otherwise re-apply
    /// and fail the same operations on every autosave, and no module would ever commit
    /// again. See CODE_AUDIT_19 §5.3.
    static let maxRollbackRetries = 3

    private struct Queue {
        var operations: [PendingOperation] = []
        /// Stamped onto each queued operation, so a newer edit for an id always wins.
        var nextSequence: UInt64 = 0
        /// The newest sequence a flush has drained per id. A rollback that re-queues an older
        /// operation after a newer one was drained must drop it, or the older full snapshot
        /// would be committed over the newer one. See CODE_AUDIT_19 §3.4.
        var latestDrained: [UUID: UInt64] = [:]
    }

    private let queue = Mutex<Queue>(Queue())
    private let flushChain = Mutex<Task<Void, Error>?>(nil)
    /// Operations already applied to the shared context by a flush but not yet committed by a
    /// `context.save()`. A rollback of the shared context (any module's failed save) discards
    /// them from the context, so they are put back in the queue instead of being lost.
    /// See CODE_AUDIT_18 §5.3.
    private let inFlight = Mutex<[PendingOperation]>([])
    /// Ids of items created locally whose insert has not been committed yet. The sync-deletion
    /// diff must never treat these as remotely deleted. See CODE_AUDIT_18 §5.2.
    private let unsavedInserts = Mutex<Set<UUID>>([])

    func addPendingOperation(_ operation: PendingOperation) {
        queue.withLock { queue in
            var operation = operation
            queue.nextSequence += 1
            operation.sequence = queue.nextSequence
            queue.operations.append(operation)
        }
    }

    /// Puts operations that could not be applied back *in front of* anything queued since they
    /// were drained: re-adding them behind newer edits would let the older state win the
    /// last-wins merge of the next flush (CODE_AUDIT_16 §3.12). An operation superseded by a
    /// newer one a flush already drained is dropped instead (CODE_AUDIT_19 §3.4).
    func restorePendingOperations(_ restored: [PendingOperation]) {
        queue.withLock { queue in
            let current = restored.filter { operation in
                queue.latestDrained[operation.id].map { $0 <= operation.sequence } ?? true
            }
            queue.operations.insert(contentsOf: current, at: 0)
        }
    }

    func clearPendingOperations() -> [PendingOperation] {
        queue.withLock { queue in
            let cleared = queue.operations
            queue.operations.removeAll()
            for operation in cleared where operation.sequence > queue.latestDrained[operation.id, default: 0] {
                queue.latestDrained[operation.id] = operation.sequence
            }
            return cleared
        }
    }

    /// Drops any queued edit for `id`. Called when the sync layer reports the item
    /// deleted elsewhere, so a pending local edit made just before the remote
    /// deletion arrived can't resurrect the item on the next flush (insert, since
    /// its id is no longer found to exist). See CODE_AUDIT_17 §5.7.
    func removePendingOperations(for id: UUID) {
        queue.withLock { queue in
            queue.operations.removeAll { $0.id == id }
            queue.latestDrained[id] = nil
        }
        inFlight.withLock { $0.removeAll { $0.id == id } }
        unsavedInserts.withLock { _ = $0.remove(id) }
    }

    /// Whether a local edit of `id` is queued or flushed into the context but not committed.
    /// The sync merge must not overwrite such an item with the store row. See CODE_AUDIT_Edit_Save §3.1.
    func hasPendingOperation(for id: UUID) -> Bool {
        queue.withLock { queue in queue.operations.contains { $0.id == id } }
            || inFlight.withLock { flushed in flushed.contains { $0.id == id } }
    }

    /// Whether an edit a failed save rolled back is still waiting for its retry.
    /// See CODE_AUDIT_20 §5.11.
    var hasRetryingOperations: Bool {
        queue.withLock { queue in queue.operations.contains { $0.rollbackCount > 0 } }
            || inFlight.withLock { flushed in flushed.contains { $0.rollbackCount > 0 } }
    }

    func markUnsavedInsert(_ id: UUID) {
        unsavedInserts.withLock { _ = $0.insert(id) }
    }

    func unsavedInsertIds() -> Set<UUID> {
        unsavedInserts.withLock { $0 }
    }

    /// Records operations that a flush applied to the context. Call on the context's queue so
    /// the record is ordered with the context's own save/rollback.
    func markInFlight(_ applied: [PendingOperation]) {
        inFlight.withLock { $0.append(contentsOf: applied) }
    }

    /// The context committed: everything flushed so far is on disk.
    func commitInFlight() {
        let committedIds = inFlight.withLock { flushed -> Set<UUID> in
            let ids = Set(flushed.map(\.id))
            flushed.removeAll()
            return ids
        }
        guard !committedIds.isEmpty else { return }
        let stillQueued = Set(queue.withLock { $0.operations.map(\.id) })
        unsavedInserts.withLock { inserts in
            inserts.subtract(committedIds.subtracting(stillQueued))
        }
    }

    /// The context rolled back: re-queue what the rollback discarded, in front of newer edits.
    ///
    /// An operation for one of `failingIds` (the objects the failed save named) or one that
    /// has already been re-queued `maxRollbackRetries` times is discarded instead, so a
    /// persistent error in one item can't stall every module's persistence. Returns the
    /// discarded operations. See CODE_AUDIT_19 §5.3.
    @discardableResult
    func restoreInFlight(failingIds: Set<UUID> = []) -> [PendingOperation] {
        let flushed = inFlight.withLock { flushed -> [PendingOperation] in
            let restored = flushed
            flushed.removeAll()
            return restored
        }
        guard !flushed.isEmpty else { return [] }
        var restored: [PendingOperation] = []
        var discarded: [PendingOperation] = []
        // With the failing items identified, only they are blamed: the other operations are
        // innocent, so a bad item cannot use up their retries. Without an identification every
        // rollback counts, which still bounds the retries. See CODE_AUDIT_20 §5.5.
        let isIdentified = !failingIds.isEmpty
        for var operation in flushed {
            if !isIdentified || failingIds.contains(operation.id) {
                operation.rollbackCount += 1
            }
            if failingIds.contains(operation.id) || operation.rollbackCount > Self.maxRollbackRetries {
                discarded.append(operation)
            } else {
                restored.append(operation)
            }
        }
        restorePendingOperations(restored)
        return discarded
    }

    /// Runs `work` only after any previously-chained flush has finished, atomically swapping
    /// in the new task under one lock acquisition so two concurrent `flushPendingOperations()`/
    /// `save()` calls on this controller (e.g. an autosave debounce racing an explicit save)
    /// can never both observe "no predecessor" and run their dequeue→existence check→apply
    /// sequences in parallel — which could let an older call's apply step land after (and
    /// silently overwrite) a newer one's. See CODE_AUDIT §3.3.
    func chainedFlush(_ work: @escaping @Sendable () async throws -> Void) async throws {
        let task = flushChain.withLock { chain -> Task<Void, Error> in
            let previous = chain
            let newTask = Task<Void, Error> {
                _ = await previous?.result
                try await work()
            }
            chain = newTask
            return newTask
        }
        try await task.value
    }
}

struct PendingOperation: Sendable {
    let id: UUID
    // `any Sendable` (not `any ModelType`) so both live-model copies and the new
    // snapshot structs can ride the same queue — ModelType is Sendable, so the
    // legacy path is unaffected.
    let model: any Sendable
    let updater: @Sendable (any Sendable, NSManagedObject) -> Void
    /// Deletes the row instead of applying `model`. Deletes ride the queue so a rollback
    /// re-queues them like any other flushed edit. See CODE_AUDIT_19 §5.4.
    var isDeletion = false
    /// Assigned by `CoreDataModel.addPendingOperation`; orders edits to the same id.
    var sequence: UInt64 = 0
    /// How often a rollback has re-queued this operation. See CODE_AUDIT_19 §5.3.
    var rollbackCount = 0

    static func deletion(of id: UUID) -> PendingOperation {
        PendingOperation(id: id, model: id, updater: { _, _ in }, isDeletion: true)
    }
}
