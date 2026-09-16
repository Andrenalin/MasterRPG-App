// @copyright André Trettin

import Combine
@preconcurrency import CoreData
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
    private let operations = Mutex<[PendingOperation]>([])
    private let flushChain = Mutex<Task<Void, Error>?>(nil)

    func addPendingOperation(_ operation: PendingOperation) {
        operations.withLock { $0.append(operation) }
    }

    func clearPendingOperations() -> [PendingOperation] {
        operations.withLock { pending in
            let cleared = pending
            pending.removeAll()
            return cleared
        }
    }

    /// Runs `work` only after any previously-chained flush has finished, atomically swapping
    /// in the new task under one lock acquisition so two concurrent `flushPendingOperations()`/
    /// `save()` calls on this controller (e.g. an autosave debounce racing an explicit save)
    /// can never both observe "no predecessor" and run their dequeue→batchExists→apply
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
    }
}

// MARK: - Single Operations (Existing)

public extension CoreDataController {
    func delete(data: DataType) async {
        guard let uuid = data.uuid else { return }
        try? await delete(uuid: uuid)
    }

    func delete(uuid: UUID) async throws {
        await context.perform {
            deleteCoreData(id: uuid, save: false)
        }
    }

    func fetch(mapper: @escaping @Sendable (DataType) -> Model) async throws -> [Model] {
        await context.perform {
            let request: NSFetchRequest<NSFetchRequestResult> = DataType.fetchRequest()
            // Prefetch relationships to avoid N+1 queries.
            // No fetchBatchSize here — batched fetches disable relationship prefetching,
            // and the result set is mapped in full right away anyway.
            if !relationshipKeyPaths.isEmpty {
                request.relationshipKeyPathsForPrefetching = relationshipKeyPaths
            }
            // Disable faulting to force immediate hydration and avoid lazy loading overhead
            request.returnsObjectsAsFaults = false
            return fetchAndDelete(request: request, mapper: mapper)
        }
    }

    func fetchIds() async throws -> [UUID] {
        await context.perform {
            let request: NSFetchRequest<NSFetchRequestResult> = DataType.fetchRequest()
            return fetchId(request: request)
        }
    }

    func fetch(uuid: UUID, mapper: @escaping @Sendable (DataType) -> Model) async throws -> Model? {
        await context.perform {
            guard let data = fetchCoreData(uuid: uuid) else { return nil }
            return mapper(data)
        }
    }

    func replace(uuid: UUID, with viewModel: Model, updater: @escaping @Sendable (Model, DataType) -> Void) async throws {
        await context.perform {
            if let current = fetchCoreData(uuid: uuid) {
                updater(viewModel, current)
            } else {
                Logger.coreDataController.debug("add new \(uuid, privacy: .public)")
                let new = DataType(context: context)
                updater(viewModel, new)
            }
        }
    }

    /// Queue a replace operation to be executed later during save.
    /// Synchronous on purpose: callers rely on the operation being enqueued in call
    /// order and being visible to any subsequent `save()`/`flushPendingOperations()`.
    func queueReplace(uuid: UUID, with viewModel: Model, updater: @escaping @Sendable (Model, DataType) -> Void) {
        let operation = PendingOperation(
            id: uuid,
            model: viewModel,
            updater: { model, nsObject in
                guard let typedModel = model as? Model,
                      let typedObject = nsObject as? DataType else { return }
                updater(typedModel, typedObject)
            }
        )
        model.addPendingOperation(operation)
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
    /// covers every module's changes. Direct callers (`addNew`, `delete`, `batchReplace`) use
    /// `save()` instead, which flushes and saves immediately.
    func flushPendingOperations() async throws {
        try await model.chainedFlush {
            let pendingOperations = model.clearPendingOperations()
            guard !pendingOperations.isEmpty else { return }

            var operationsByID: [UUID: PendingOperation] = [:]
            for operation in pendingOperations {
                operationsByID[operation.id] = operation
            }
            let uniqueOperations = Array(operationsByID.values)
            let existingUUIDs = try await batchExists(uuids: uniqueOperations.map { $0.id })

            await context.perform {
                for operation in uniqueOperations {
                    if existingUUIDs.contains(operation.id) {
                        if let existing = self.fetchCoreData(uuid: operation.id) {
                            operation.updater(operation.model, existing)
                        }
                    } else {
                        let new = DataType(context: self.context)
                        operation.updater(operation.model, new)
                    }
                }
            }
        }
    }

    func save() async throws {
        try await flushPendingOperations()
        try await context.perform {
            try saveCoreDataThrowing()
        }
    }
}

// MARK: - Snapshot Operations
//
// Sendable-snapshot variants of the fetch/replace paths. Mapping runs entirely on
// the context queue and only value types cross out — used by modules whose domain
// models are @MainActor and therefore must not be touched on the Core Data queue.

public extension CoreDataController {
    /// Mirrors fetch(mapper:) including relationship prefetching and duplicate repair.
    func fetchSnapshots<Snapshot: Sendable>(mapper: @escaping @Sendable (DataType) -> Snapshot) async throws -> [Snapshot] {
        await context.perform {
            let request: NSFetchRequest<NSFetchRequestResult> = DataType.fetchRequest()
            // Prefetch relationships to avoid N+1 queries.
            // No fetchBatchSize here — batched fetches disable relationship prefetching,
            // and the result set is mapped in full right away anyway.
            if !relationshipKeyPaths.isEmpty {
                request.relationshipKeyPathsForPrefetching = relationshipKeyPaths
            }
            request.returnsObjectsAsFaults = false
            return fetchAndDelete(request: request, mapper: mapper)
        }
    }

    func fetchSnapshot<Snapshot: Sendable>(uuid: UUID, mapper: @escaping @Sendable (DataType) -> Snapshot) async throws -> Snapshot? {
        await context.perform {
            guard let data = fetchCoreData(uuid: uuid) else { return nil }
            return mapper(data)
        }
    }

    func replace<Snapshot: Sendable>(uuid: UUID, snapshot: Snapshot, updater: @escaping @Sendable (Snapshot, DataType) -> Void) async throws {
        await context.perform {
            if let current = fetchCoreData(uuid: uuid) {
                updater(snapshot, current)
            } else {
                Logger.coreDataController.debug("add new \(uuid, privacy: .public)")
                let new = DataType(context: context)
                updater(snapshot, new)
            }
        }
    }

    /// Mirrors batchReplace(models:...) — single upfront existence check, chunked apply, one save.
    func batchReplace<Snapshot: Sendable>(
        snapshots: [Snapshot],
        keyPath: KeyPath<Snapshot, UUID>,
        updater: @escaping @Sendable (Snapshot, DataType) -> Void,
        chunkSize: Int = 100
    ) async throws {
        guard !snapshots.isEmpty else { return }

        let allUUIDs = snapshots.map { $0[keyPath: keyPath] }
        let existingUUIDs = try await batchExists(uuids: allUUIDs)

        for chunk in snapshots.chunked(into: chunkSize) {
            await context.perform {
                for snapshot in chunk {
                    let uuid = snapshot[keyPath: keyPath]
                    if existingUUIDs.contains(uuid) {
                        if let existing = fetchCoreData(uuid: uuid) {
                            updater(snapshot, existing)
                        }
                    } else {
                        let new = DataType(context: context)
                        updater(snapshot, new)
                    }
                }
            }
        }

        try await save()
        Logger.coreDataController.info("Batch replaced \(snapshots.count) snapshots")
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
            await context.perform {
                let request: NSFetchRequest<NSFetchRequestResult> = DataType.fetchRequest()
                request.predicate = NSPredicate(format: "uuid IN %@", chunk as [NSUUID])
                request.includesPropertyValues = false

                do {
                    let objects = try context.fetch(request) as? [DataType] ?? []
                    objects.forEach { context.delete($0) }
                    saveCoreData()
                } catch {
                    Logger.coreDataController.error("Batch delete error: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        Logger.coreDataController.info("Batch deleted \(uuids.count) objects")
    }
    
    /// Batch replace/insert operations with automatic chunking
    func batchReplace(
        models: [Model],
        keyPath: KeyPath<Model, UUID>,
        updater: @escaping @Sendable (Model, DataType) -> Void,
        chunkSize: Int = 100
    ) async throws {
        guard !models.isEmpty else { return }

        // Single existence check for all models upfront — avoids one SQL query per chunk.
        let allUUIDs = models.map { $0[keyPath: keyPath] }
        let existingUUIDs = try await batchExists(uuids: allUUIDs)

        let chunks = models.chunked(into: chunkSize)
        for chunk in chunks {
            try await processBatchChunk(chunk: chunk, keyPath: keyPath, existingUUIDs: existingUUIDs, updater: updater)
        }

        // Save once after all chunks are processed
        try await save()
        Logger.coreDataController.info("Batch replaced \(models.count) objects in \(chunks.count) chunks")
    }
    
    /// Batch exists check for multiple UUIDs
    func batchExists(uuids: [UUID]) async throws -> Set<UUID> {
        guard !uuids.isEmpty else { return Set() }
        
        return await context.perform {
            let request = NSFetchRequest<NSDictionary>(entityName: String(describing: DataType.self))
            request.predicate = NSPredicate(format: "uuid IN %@", uuids as [NSUUID])
            request.propertiesToFetch = ["uuid"]
            request.resultType = .dictionaryResultType
            
            do {
                let results = try context.fetch(request)
                let existingUUIDs = results.compactMap { dict in
                    dict["uuid"] as? UUID
                }
                return Set(existingUUIDs)
            } catch {
                Logger.coreDataController.error("Batch exists check error: \(error.localizedDescription, privacy: .public)")
                return Set()
            }
        }
    }
}

// MARK: - Private Batch Helpers

private extension CoreDataController {
    func processBatchChunk(
        chunk: [Model],
        keyPath: KeyPath<Model, UUID>,
        existingUUIDs: Set<UUID>,
        updater: @escaping @Sendable (Model, DataType) -> Void
    ) async throws {
        await context.perform {
            for model in chunk {
                let uuid = model[keyPath: keyPath]
                if existingUUIDs.contains(uuid) {
                    if let existing = fetchCoreData(uuid: uuid) {
                        updater(model, existing)
                    }
                } else {
                    let new = DataType(context: context)
                    updater(model, new)
                }
            }
        }
    }
}

// MARK: - Core Data Background Task (Existing)

private extension CoreDataController {
    func fetchAndDelete<T>(request: NSFetchRequest<NSFetchRequestResult>, mapper: @escaping @Sendable (DataType) -> T?) -> [T] {
        do {
            guard let data = try self.context.fetch(request) as? [DataType] else {
                Logger.coreDataController.error("fetch returned an unexpected object type; expected \(DataType.self)")
                return []
            }
            var seenId: Set<UUID> = []
            var foundDuplicates = false
            let models = data.compactMap { item -> T? in
                guard let id = item.uuid else { return nil }
                guard !seenId.contains(id) else {
                    Logger.coreDataController.warning("duplicate uuid \(id, privacy: .public) - delete coredata object")
                    context.delete(item)
                    foundDuplicates = true
                    return nil
                }
                seenId.insert(id)
                return mapper(item)
            }
            // Save the repair right away so the deletions form their own transaction
            // instead of riding along with the next unrelated save.
            if foundDuplicates {
                saveCoreData()
            }
            return models
        } catch {
            Logger.coreDataController.error("fetch error \(error.localizedDescription, privacy: .public)")
        }
        return []
    }

    func fetchId(request: NSFetchRequest<NSFetchRequestResult>) -> [UUID] {
        do {
            guard let data = try self.context.fetch(request) as? [DataType] else {
                Logger.coreDataController.error("fetch returned an unexpected object type; expected \(DataType.self)")
                return []
            }
            var seenId: Set<UUID> = []
            var foundDuplicates = false
            let ids = data.compactMap { item -> UUID? in
                guard let id = item.uuid else { return nil }
                guard !seenId.contains(id) else {
                    Logger.coreDataController.warning("duplicate uuid \(id, privacy: .public) - delete coredata object")
                    context.delete(item)
                    foundDuplicates = true
                    return nil
                }
                seenId.insert(id)
                return id
            }
            if foundDuplicates {
                saveCoreData()
            }
            return ids
        } catch {
            Logger.coreDataController.error("fetch error \(error.localizedDescription, privacy: .public)")
        }
        return []
    }

    func fetch(uuid: UUID) async throws -> DataType? {
        await context.perform {
            fetchCoreData(uuid: uuid)
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
            Logger.coreDataController.error("fetch id \(uuid, privacy: .public) error \(error.localizedDescription, privacy: .public)")
        }
        return nil
    }

    func addNewCoreData(id: UUID, model: Model, updater: @escaping @Sendable (Model, DataType) -> Void) {
        Logger.coreDataController.debug("add new \(id, privacy: .public)")
        context.perform {
            let new = DataType(context: context)
            updater(model, new)
        }
    }

    func deleteCoreData(id: UUID, save: Bool = true) {
        Logger.coreDataController.debug("going to delete \(id, privacy: .public)")
        guard let object = fetchCoreData(uuid: id) else { return }
        context.delete(object)
        if save {
            saveCoreData()
        }
        Logger.coreDataController.debug("deleted \(id, privacy: .public)")
    }
    
    func saveCoreData() {
        do {
            try saveCoreDataThrowing()
        } catch {
            Logger.coreDataController.error("save error \(error.localizedDescription, privacy: .public)")
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
