// @copyright André Trettin

import Combine
@preconcurrency import CoreData
import os.log
import SwiftUI

public protocol CoreDataId {
    var uuid: UUID? { get }
}

actor CoreDataModel: Sendable {
    private(set) var updatedIds: Set<UUID> = []
    private(set) var pendingOperations: [PendingOperation] = []

    func addPendingOperation(_ operation: PendingOperation) {
        pendingOperations.append(operation)
    }

    func clearPendingOperations() -> [PendingOperation] {
        let operations = pendingOperations
        pendingOperations.removeAll()
        return operations
    }
}

struct PendingOperation: Sendable {
    let id: UUID
    let model: any ModelType
    let updater: @Sendable (any ModelType, NSManagedObject) -> Void
}

public struct CoreDataController<Model: ModelType, DataType: NSManagedObject & CoreDataId>: Sendable {
    let model: CoreDataModel

    private let context: NSManagedObjectContext
    private let batchContext: NSManagedObjectContext
    private let relationshipKeyPaths: [String]

    @MainActor
    public init(
        context: NSManagedObjectContext,
        batchContext: NSManagedObjectContext? = nil,
        relationshipKeyPaths: [String] = []
    ) {
        self.context = context
        self.batchContext = batchContext ?? context
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
            // Prefetch relationships to avoid N+1 queries
            if !relationshipKeyPaths.isEmpty {
                request.relationshipKeyPathsForPrefetching = relationshipKeyPaths
                request.fetchBatchSize = 20
            }
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

    /// Queue a replace operation to be executed later during save
    func queueReplace(uuid: UUID, with viewModel: Model, updater: @escaping @Sendable (Model, DataType) -> Void) async {
        let operation = PendingOperation(
            id: uuid,
            model: viewModel,
            updater: { model, nsObject in
                guard let typedModel = model as? Model,
                      let typedObject = nsObject as? DataType else { return }
                updater(typedModel, typedObject)
            }
        )
        await model.addPendingOperation(operation)
    }

    func save() async throws {
        // First, process any pending operations
        let pendingOperations = await model.clearPendingOperations()

        if !pendingOperations.isEmpty {
            // Group operations by ID to handle duplicates (keep last)
            var operationsByID: [UUID: PendingOperation] = [:]
            for operation in pendingOperations {
                operationsByID[operation.id] = operation
            }

            let uniqueOperations = Array(operationsByID.values)
            let uuids = uniqueOperations.map { $0.id }

            // Check which objects exist
            let existingUUIDs = try await batchExists(uuids: uuids)

            // Process all operations in one context.perform block
            await context.perform {
                for operation in uniqueOperations {
                    if existingUUIDs.contains(operation.id) {
                        // Update existing
                        if let existing = self.fetchCoreData(uuid: operation.id) {
                            operation.updater(operation.model, existing)
                        }
                    } else {
                        // Create new
                        let new = DataType(context: self.context)
                        operation.updater(operation.model, new)
                    }
                }
            }
        }

        // Then save
        await context.perform {
            saveCoreData()
        }
    }
}

// MARK: - Batch Operations (New)

public extension CoreDataController {
    
    /// Batch delete using NSBatchDeleteRequest for better performance
    func batchDelete(uuids: [UUID]) async throws {
        guard !uuids.isEmpty else { return }

        try await batchContext.perform {
            let request = NSFetchRequest<NSFetchRequestResult>(entityName: String(describing: DataType.self))
            request.predicate = NSPredicate(format: "uuid IN %@", uuids as [NSUUID])

            let batchDeleteRequest = NSBatchDeleteRequest(fetchRequest: request)
            batchDeleteRequest.resultType = .resultTypeObjectIDs

            do {
                let result = try self.batchContext.execute(batchDeleteRequest) as? NSBatchDeleteResult
                let objectIDArray = result?.result as? [NSManagedObjectID]
                let changes = [NSDeletedObjectsKey: objectIDArray ?? []]

                // Merge changes to both batchContext and main context to ensure immediate consistency
                NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [self.batchContext, self.context])

                Logger.coreDataController.info("Batch deleted \(uuids.count) objects")
            } catch {
                Logger.coreDataController.error("Batch delete error: \(error.localizedDescription, privacy: .public)")
                throw error
            }
        }
    }
    
    /// Batch replace/insert operations with automatic chunking
    func batchReplace(
        models: [Model], 
        keyPath: KeyPath<Model, UUID>,
        updater: @escaping @Sendable (Model, DataType) -> Void,
        chunkSize: Int = 100
    ) async throws {
        guard !models.isEmpty else { return }
        
        // Process in chunks to avoid memory issues
        let chunks = models.chunked(into: chunkSize)
        
        for chunk in chunks {
            try await processBatchChunk(chunk: chunk, keyPath: keyPath, updater: updater)
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
        updater: @escaping @Sendable (Model, DataType) -> Void
    ) async throws {
        let chunkUUIDs = chunk.map { $0[keyPath: keyPath] }
        let existingUUIDs = try await batchExists(uuids: chunkUUIDs)

        await context.perform {
            for model in chunk {
                let uuid = model[keyPath: keyPath]

                if existingUUIDs.contains(uuid) {
                    // Update existing
                    if let existing = fetchCoreData(uuid: uuid) {
                        updater(model, existing)
                    }
                } else {
                    // Create new
                    let new = DataType(context: context)
                    updater(model, new)
                }
            }

            // Don't save per chunk - let batchReplace save once at the end for better performance
        }
    }
}

// MARK: - Core Data Background Task (Existing)

private extension CoreDataController {
    func fetchAndDelete(request: NSFetchRequest<NSFetchRequestResult>, mapper: @escaping @Sendable (DataType) -> Model?) -> [Model] {
        do {
            let data = try self.context.fetch(request) as! [DataType]
            var seenId: Set<UUID> = []
            return data.compactMap {
                guard let id = $0.uuid else { return nil }
                guard !seenId.contains(id) else {
                    Logger.coreDataController.warning("duplicate uuid \(id, privacy: .public) - delete coredata object")
                    context.delete($0)
                    return nil
                }
                seenId.insert(id)
                return mapper($0)
            }
        } catch {
            Logger.coreDataController.error("fetch error \(error.localizedDescription, privacy: .public)")
        }
        return []
    }

    func fetchId(request: NSFetchRequest<NSFetchRequestResult>) -> [UUID] {
        do {
            let data = try self.context.fetch(request) as! [DataType]
            var seenId: Set<UUID> = []
            return data.compactMap {
                guard let id = $0.uuid else { return nil }
                guard !seenId.contains(id) else {
                    Logger.coreDataController.warning("duplicate uuid \(id, privacy: .public) - delete coredata object")
                    context.delete($0)
                    return nil
                }
                seenId.insert(id)
                return id
            }
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
            let objects = try context.fetch(fetchId) as! [DataType]
            let result = objects.first
            if objects.count > 1 {
                Logger.coreDataController.warning("fetch id \(uuid, privacy: .public) has \(objects.count) objects")
                let delObjs = objects.dropFirst()
                delObjs.forEach {
                    context.delete($0)
                }
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
            if context.hasChanges {
                Logger.coreDataController.debug("save changes")
                try context.save()
            }
        } catch {
            Logger.coreDataController.error("save error \(error.localizedDescription, privacy: .public)")
        }
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
