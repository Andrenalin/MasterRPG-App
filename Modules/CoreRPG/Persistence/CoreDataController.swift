// @copyright André Trettin

import CoreData
import os.log
import SwiftUI
import Synchronization

public protocol CoreDataId {
    var uuid: UUID? { get }
}

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

public struct CoreDataController<Model: ModelType, DataType: NSManagedObject & CoreDataId>: Sendable {
    let model: CoreDataModel

    private let context: NSManagedObjectContext
    private let relationshipKeyPaths: [String]

    @MainActor
    public init(
        context: NSManagedObjectContext,
        relationshipKeyPaths: [String] = []
    ) {
        self.context = context
        self.relationshipKeyPaths = relationshipKeyPaths
        model = CoreDataModel()
        ContextFlushLedger.shared.register(model, for: context)
    }
}

// MARK: - Single Operations (Existing)

public extension CoreDataController {
    func delete(data: DataType) async {
        guard let uuid = data.uuid else { return }
        try? await delete(uuid: uuid)
    }

    /// Queues the deletion and flushes it into the context without saving. A direct
    /// `context.delete` was not recorded as in flight, so another module's failed save could
    /// roll it back: the item came back on disk after relaunch while it stayed gone in memory.
    /// See CODE_AUDIT_19 §5.4.
    func delete(uuid: UUID) async throws {
        model.addPendingOperation(.deletion(of: uuid))
        try await flushPendingOperations()
    }

    func fetchIds() async throws -> [UUID] {
        try await context.perform {
            let request: NSFetchRequest<NSFetchRequestResult> = DataType.fetchRequest()
            return try fetchId(request: request)
        }
    }

    /// Snapshot variant: queue a replace whose payload is a plain Sendable value,
    /// applied on the context queue during the next flush/save.
    func queueReplace<Snapshot: Sendable>(uuid: UUID, snapshot: Snapshot, updater: @escaping @Sendable (Snapshot, DataType) -> Void) {
        let operation = PendingOperation(
            id: uuid,
            model: snapshot,
            updater: { value, nsObject in
                guard let typedSnapshot = value as? Snapshot,
                      let typedObject = nsObject as? DataType else { return }
                updater(typedSnapshot, typedObject)
            }
        )
        model.addPendingOperation(operation)
    }

    /// Drains the pending-operations queue into the context without calling `context.save()`.
    /// Use from `AdventureRootModel.save()` for all module roots so a single `context.save()`
    /// covers every module's changes. `replace` and `delete` queue their
    /// writes and flush too, so every write into the shared context is recorded as in flight
    /// and survives another module's rollback. See CODE_AUDIT_19 §5.4.
    func flushPendingOperations() async throws {
        try await model.chainedFlush {
            let pendingOperations = model.clearPendingOperations()
            guard !pendingOperations.isEmpty else { return }

            var operationsByID: [UUID: PendingOperation] = [:]
            for operation in pendingOperations where operation.sequence >= operationsByID[operation.id]?.sequence ?? 0 {
                operationsByID[operation.id] = operation
            }
            let uniqueOperations = Array(operationsByID.values)
            // The existence check and the apply share one `perform` block: with a gap between
            // them a CloudKit merge could delete (edit silently dropped) or create (duplicate
            // uuid row) the record in between. See CODE_AUDIT_16 §3.11.
            do {
                try await context.perform {
                    // One fetch for all rows. After the batched existence check every update and
                    // delete fetched its row on its own: n single-row fetches for an import of
                    // n items. See CODE_AUDIT_21 §7.4.
                    let existingRows = try self.existingRowsInContext(uniqueOperations.map { $0.id })
                    for operation in uniqueOperations {
                        if operation.isDeletion {
                            if let existing = existingRows[operation.id] {
                                self.context.delete(existing)
                            }
                        } else if let existing = existingRows[operation.id] {
                            operation.updater(operation.model, existing)
                        } else {
                            let new = DataType(context: self.context)
                            operation.updater(operation.model, new)
                        }
                    }
                    // Recorded on the context queue, ordered with any save/rollback of the
                    // shared context, so a later rollback can re-queue exactly these.
                    // See CODE_AUDIT_18 §5.3.
                    model.markInFlight(uniqueOperations)
                }
            } catch {
                // The queue was already drained; put the operations back so a retry does not
                // silently drop these edits. See CODE_AUDIT_15 §5.6.
                model.restorePendingOperations(pendingOperations)
                throw error
            }
        }
    }

    func save() async throws {
        try await flushPendingOperations()
        do {
            try await context.perform {
                try saveCoreDataThrowing()
            }
        } catch {
            // Unlike `batchDelete`, this used to leave a failed save's invalid managed
            // objects registered in the context, so every later save re-attempted the
            // same invalid set and failed until relaunch. Roll back so the context
            // returns to its last-saved state instead (CODE_AUDIT_17 §5.6), and re-queue
            // every module's flushed-but-unsaved edits the rollback discarded, so they are
            // retried instead of lost (CODE_AUDIT_18 §5.3). The objects the error names are
            // quarantined rather than retried (CODE_AUDIT_19 §5.3).
            await context.perform {
                context.rollbackRestoringFlushedOperations(after: error)
            }
            throw error
        }
    }
}

// MARK: - Snapshot Operations
//
// Sendable-snapshot variants of the fetch/replace paths. Mapping runs entirely on
// the context queue and only value types cross out — used by modules whose domain
// models are @MainActor and therefore must not be touched on the Core Data queue.

public extension CoreDataController {
    /// Fetches every row as a snapshot, with relationship prefetching and duplicate repair.
    func fetchSnapshots<Snapshot: Sendable>(mapper: @escaping @Sendable (DataType) -> Snapshot) async throws -> [Snapshot] {
        try await context.perform {
            let request: NSFetchRequest<NSFetchRequestResult> = DataType.fetchRequest()
            // Prefetch relationships to avoid N+1 queries.
            // No fetchBatchSize here — batched fetches disable relationship prefetching,
            // and the result set is mapped in full right away anyway.
            if !relationshipKeyPaths.isEmpty {
                request.relationshipKeyPathsForPrefetching = relationshipKeyPaths
            }
            request.returnsObjectsAsFaults = false
            return try fetchAndDelete(request: request, mapper: mapper)
        }
    }

    func fetchSnapshot<Snapshot: Sendable>(uuid: UUID, mapper: @escaping @Sendable (DataType) -> Snapshot) async throws -> Snapshot? {
        await context.perform {
            guard let data = fetchCoreData(uuid: uuid) else { return nil }
            return mapper(data)
        }
    }

    /// Queues the replace and flushes it into the context without saving, so the write is
    /// recorded as in flight and re-queued by a rollback. See CODE_AUDIT_19 §5.4.
    func replace<Snapshot: Sendable>(uuid: UUID, snapshot: Snapshot, updater: @escaping @Sendable (Snapshot, DataType) -> Void) async throws {
        queueReplace(uuid: uuid, snapshot: snapshot, updater: updater)
        try await flushPendingOperations()
    }
}

// MARK: - Batch Operations (New)

public extension CoreDataController {
    
    /// Batch delete in chunks through the context, NOT via NSBatchDeleteRequest.
    /// NSPersistentCloudKitContainer does not support batch requests — they bypass the
    /// context save, so the mirroring delegate never exports the deletions and other
    /// devices resurrect the items. Context deletes + save sync normally.
    func batchDelete(uuids: [UUID], chunkSize: Int = 100) async throws {
        guard !uuids.isEmpty else { return }

        for chunk in uuids.chunked(into: chunkSize) {
            // Errors propagate: a failed save used to be logged while "Batch deleted" was
            // still reported and the objects stayed pending in the context.
            // See CODE_AUDIT_15 §5.6.
            try await context.perform {
                let request: NSFetchRequest<NSFetchRequestResult> = DataType.fetchRequest()
                request.predicate = NSPredicate(format: "uuid IN %@", chunk as [NSUUID])
                request.includesPropertyValues = false

                do {
                    let objects = try context.fetch(request) as? [DataType] ?? []
                    objects.forEach { context.delete($0) }
                    try saveCoreDataThrowing()
                } catch {
                    Logger.coreDataController.error("Batch delete error: \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
                    context.rollbackRestoringFlushedOperations(after: error)
                    throw error
                }
            }
        }
        Logger.coreDataController.info("Batch deleted \(uuids.count) objects")
    }

    /// Batch exists check for multiple UUIDs
    /// Must be called on the context's queue. A failed lookup throws rather than reading as
    /// "nothing exists".
    /// The rows with these uuids, as the context sees them: an object fetch includes the
    /// context's unsaved inserts and leaves out its unsaved deletes, which is what
    /// a dictionary fetch would have to work out by hand. Of rows sharing a
    /// uuid the first fetched is taken, as `fetchCoreData(uuid:)` does.
    /// See CODE_AUDIT_20 §5.7, CODE_AUDIT_21 §7.4.
    func existingRowsInContext(_ uuids: [UUID]) throws -> [UUID: DataType] {
        guard !uuids.isEmpty else { return [:] }
        let request = DataType.fetchRequest()
        request.predicate = NSPredicate(format: "uuid IN %@", uuids as [NSUUID])
        request.includesPendingChanges = true
        guard let rows = try context.fetch(request) as? [DataType] else { return [:] }
        var rowsByUUID: [UUID: DataType] = [:]
        for row in rows where !row.isDeleted {
            guard let uuid = row.uuid, rowsByUUID[uuid] == nil else { continue }
            rowsByUUID[uuid] = row
        }
        return rowsByUUID
    }
}

// MARK: - Core Data Background Task (Existing)

private extension CoreDataController {
    // Rethrows rather than swallowing a fetch failure into an empty `[]` result: the
    // full-table reconciliation caller (`SyncDataControllable.fetchUpdates()`) treats
    // an empty result as "everything was deleted", which would otherwise wipe the
    // in-memory item list (and previously the files too, see §5.1) on a transient
    // fetch failure. See CODE_AUDIT_17 §5.1.
    func fetchAndDelete<T>(request: NSFetchRequest<NSFetchRequestResult>, mapper: @escaping @Sendable (DataType) -> T?) throws -> [T] {
        do {
            guard let data = try self.context.fetch(request) as? [DataType] else {
                Logger.coreDataController.error("fetch returned an unexpected object type; expected \(DataType.self)")
                return []
            }
            var foundDuplicates = false
            // Which duplicate survives must not depend on the fetch order, nor on this device:
            // see `duplicateSurvivors`. The fetch (sort) order of the returned models is kept.
            // See CODE_AUDIT_15 §5.6, CODE_AUDIT_21 §5.7.
            let survivors = duplicateSurvivors(in: data)
            let models = data.compactMap { item -> T? in
                guard let id = item.uuid else { return nil }
                guard survivors[id] == item.objectID else {
                    Logger.coreDataController.warning("duplicate uuid \(id, privacy: .public) - delete coredata object")
                    context.delete(item)
                    foundDuplicates = true
                    return nil
                }
                return mapper(item)
            }
            // Save the repair right away so the deletions form their own transaction
            // instead of riding along with the next unrelated save.
            if foundDuplicates {
                saveCoreData()
            }
            return models
        } catch {
            Logger.coreDataController.error("fetch error \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
            throw error
        }
    }

    /// The row to keep per uuid. Where several rows share a uuid, the one every device picks:
    /// see `DuplicateRowOrder`. See CODE_AUDIT_21 §5.7.
    func duplicateSurvivors(in data: [DataType]) -> [UUID: NSManagedObjectID] {
        var rowsById: [UUID: [DataType]] = [:]
        for item in data {
            guard let id = item.uuid else { continue }
            rowsById[id, default: []].append(item)
        }
        return rowsById.compactMapValues { rows in
            rows.count == 1 ? rows[0].objectID : DuplicateRowOrder.sorted(rows).first?.objectID
        }
    }

    /// Rethrows a fetch failure: the sync-deletion diff treats a missing id as a remote
    /// deletion, so an empty result on error would empty the whole module in memory and drop
    /// every pending edit in it. See CODE_AUDIT_18 §5.2.
    func fetchId(request: NSFetchRequest<NSFetchRequestResult>) throws -> [UUID] {
        do {
            guard let data = try self.context.fetch(request) as? [DataType] else {
                Logger.coreDataController.error("fetch returned an unexpected object type; expected \(DataType.self)")
                throw CocoaError(.coderReadCorrupt)
            }
            var foundDuplicates = false
            // The same survivor as `fetchAndDelete` picks: this kept whichever row the fetch
            // returned first. See CODE_AUDIT_21 §5.7.
            let survivors = duplicateSurvivors(in: data)
            let ids = data.compactMap { item -> UUID? in
                guard let id = item.uuid else { return nil }
                guard survivors[id] == item.objectID else {
                    Logger.coreDataController.warning("duplicate uuid \(id, privacy: .public) - delete coredata object")
                    context.delete(item)
                    foundDuplicates = true
                    return nil
                }
                return id
            }
            if foundDuplicates {
                saveCoreData()
            }
            return ids
        } catch {
            Logger.coreDataController.error("fetch error \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
            throw error
        }
    }

    func fetchCoreData(uuid: UUID) -> DataType? {
        let fetchId = DataType.fetchRequest()
        fetchId.predicate = NSPredicate(format: "uuid == %@", uuid as NSUUID)
        do {
            guard let objects = try context.fetch(fetchId) as? [DataType] else {
                Logger.coreDataController.error("fetch id \(uuid, privacy: .public) returned an unexpected object type; expected \(DataType.self)")
                return nil
            }
            let result = objects.first
            if objects.count > 1 {
                // Log only. This runs on every sync-triggered read — deleting here would
                // turn reads into writes that re-export to CloudKit and can ping-pong
                // between devices. Duplicates are repaired by the full fetch at startup.
                Logger.coreDataController.warning("fetch id \(uuid, privacy: .public) has \(objects.count) objects")
            }
            return result
        } catch {
            Logger.coreDataController.error("fetch id \(uuid, privacy: .public) error \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
        }
        return nil
    }

    func saveCoreData() {
        do {
            try saveCoreDataThrowing()
        } catch {
            Logger.coreDataController.error("save error \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
        }
    }

    /// Transactional save boundary used by callers which must be able to roll back after a
    /// persistent-store failure. Legacy fire-and-forget call sites continue through
    /// `saveCoreData()` and retain their existing logging behavior.
    func saveCoreDataThrowing() throws {
        guard context.hasPersistentChanges else { return }
        Logger.coreDataController.debug("save changes")

        // Log CloudKit operation before save
        Task {
            await CloudKitOperationCounter.shared.recordOperation(
                function: "CoreDataController.saveCoreData() -> context.save()",
                file: "CoreDataController.swift"
            )
        }

        try context.save()
    }
}

// MARK: - Array Extension for Chunking

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

extension Logger {
    static let coreDataController = Logger(subsystem: subsystem, category: "CoreDataController")
}

private extension NSManagedObjectContext {
    /// True only when there are changes that will produce a persistent store write.
    /// Avoids spurious context.save() calls (and the resulting CloudKit export transactions)
    /// when only transient properties or in-memory faults changed.
    var hasPersistentChanges: Bool {
        !insertedObjects.isEmpty ||
        !deletedObjects.isEmpty ||
        updatedObjects.contains { !$0.changedValues().isEmpty }
    }
}
