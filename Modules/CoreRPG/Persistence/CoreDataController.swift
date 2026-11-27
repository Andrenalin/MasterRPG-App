// @copyright André Trettin

import CoreData
import os.log
import SwiftUI
import Synchronization

public protocol CoreDataId {
    var uuid: UUID? { get }
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
                        // Rows sharing a uuid: a delete removes all of them (one left over brought
                        // the item back), an update writes the row the startup repair keeps and
                        // deletes the others (an edit of a losing row was deleted by the next
                        // launch's repair). See CODE_AUDIT_29 §5.4.
                        let rows = existingRows[operation.id] ?? []
                        if operation.isDeletion {
                            rows.forEach(self.context.delete)
                        } else if let existing = rows.first {
                            operation.updater(operation.model, existing)
                            rows.dropFirst().forEach(self.context.delete)
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
    /// a dictionary fetch would have to work out by hand. Rows sharing a uuid come in
    /// `DuplicateRowOrder`, the row the startup repair keeps first (the record-name lookup runs
    /// only for such duplicates, which are rare). See CODE_AUDIT_20 §5.7, CODE_AUDIT_21 §7.4,
    /// CODE_AUDIT_29 §5.4.
    func existingRowsInContext(_ uuids: [UUID]) throws -> [UUID: [DataType]] {
        guard !uuids.isEmpty else { return [:] }
        let request = DataType.fetchRequest()
        request.predicate = NSPredicate(format: "uuid IN %@", uuids as [NSUUID])
        request.includesPendingChanges = true
        guard let rows = try context.fetch(request) as? [DataType] else { return [:] }
        var rowsByUUID: [UUID: [DataType]] = [:]
        for row in rows where !row.isDeleted {
            guard let uuid = row.uuid else { continue }
            rowsByUUID[uuid, default: []].append(row)
        }
        return rowsByUUID.mapValues { $0.count > 1 ? DuplicateRowOrder.sorted($0) : $0 }
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
                saveDuplicateRepair()
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
                saveDuplicateRepair()
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
            // The row the startup repair keeps, not whichever the fetch returned first.
            // See CODE_AUDIT_29 §5.4.
            let result = objects.count > 1 ? DuplicateRowOrder.sorted(objects).first : objects.first
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

    /// Saves the duplicate-row repair. A failure rolls back like every other save path (and puts
    /// back the operations other modules flushed), instead of leaving the shared context dirty
    /// for the next module's save. See CODE_AUDIT_29 §5.13.
    func saveDuplicateRepair() {
        do {
            try saveCoreDataThrowing()
        } catch {
            Logger.coreDataController.error("duplicate repair save error \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
            context.rollbackRestoringFlushedOperations(after: error)
        }
    }

    /// Transactional save boundary used by callers which must be able to roll back after a
    /// persistent-store failure.
    func saveCoreDataThrowing() throws {
        guard context.hasPersistentChanges else { return }
        Logger.coreDataController.debug("save changes")
#if DEBUG
        context.logPendingSave("context")
#endif

        CloudKitOperationCounter.shared.recordOperation(function: "CoreDataController.saveCoreData() -> context.save()")

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

#if DEBUG
extension NSManagedObjectContext {
    /// Logs what the next `save()` writes: inserts and deletes per entity, and every updated object
    /// with the attributes whose value really differs from the committed one. An object that was only
    /// assigned its current values again still counts as updated (`changedValues()` is not empty), and
    /// is reported separately as "unchanged", because it makes a save that writes nothing.
    /// Must run on the context's queue.
    func logPendingSave(_ source: String) {
        let logger = Logger.coreDataController
        func counts(_ objects: Set<NSManagedObject>) -> String {
            Dictionary(grouping: objects, by: { $0.entity.name ?? "?" })
                .map { "\($0.key)×\($0.value.count)" }
                .sorted()
                .joined(separator: " ")
        }
        if !insertedObjects.isEmpty { logger.info("Save[\(source)] inserts: \(counts(self.insertedObjects), privacy: .public)") }
        if !deletedObjects.isEmpty { logger.info("Save[\(source)] deletes: \(counts(self.deletedObjects), privacy: .public)") }

        var changed: [(entity: String, uuid: String, keys: [String])] = []
        var unchanged: [String: Int] = [:]
        for object in updatedObjects {
            let values = object.changedValues()
            guard !values.isEmpty else { continue }
            let entity = object.entity.name ?? "?"
            guard object.hasPersistentChangedValues else {
                unchanged[entity, default: 0] += 1
                continue
            }
            let attributeKeys = values.keys.filter { object.entity.attributesByName[$0] != nil }
            let committed = object.committedValues(forKeys: attributeKeys)
            let differing = attributeKeys.filter { key in
                let new = values[key] as? NSObject
                let old = committed[key] as? NSObject
                return !(new?.isEqual(old) ?? (old == nil))
            }
            let relationships = values.keys.filter { object.entity.relationshipsByName[$0] != nil }
            // Not every entity has a uuid (tags do not): fall back to the row's store id.
            let uuid = object.entity.attributesByName["uuid"] != nil
                ? (object.value(forKey: "uuid") as? UUID)?.uuidString ?? "-"
                : object.objectID.uriRepresentation().lastPathComponent
            changed.append((entity, uuid, (differing + relationships.map { "\($0)(relationship)" }).sorted()))
        }
        if !unchanged.isEmpty {
            let list = unchanged.sorted { $0.key < $1.key }.map { "\($0.key)×\($0.value)" }.joined(separator: " ")
            logger.info("Save[\(source)] updated without a different value (no-op): \(list, privacy: .public)")
        }
        let byEntity = Dictionary(grouping: changed, by: \.entity)
        for (entity, rows) in byEntity.sorted(by: { $0.key < $1.key }) {
            logger.info("Save[\(source)] updates \(entity, privacy: .public)×\(rows.count)")
            for row in rows.prefix(15) {
                logger.info("  \(entity, privacy: .public) \(row.uuid, privacy: .public): \(row.keys.joined(separator: ","), privacy: .public)")
            }
            if rows.count > 15 { logger.info("  … and \(rows.count - 15) more \(entity, privacy: .public)") }
        }
    }
}
#endif
