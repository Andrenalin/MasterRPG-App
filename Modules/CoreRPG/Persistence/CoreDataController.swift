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
}

public struct CoreDataController<Model: ModelType, DataType: NSManagedObject & CoreDataId>: Sendable {
    let model: CoreDataModel

    private let context: NSManagedObjectContext

    @MainActor
    public init(context: NSManagedObjectContext) {
        self.context = context
        model = CoreDataModel()
    }
}

// MARK: - Writer

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
        if let current = try await fetch(uuid: uuid) {
            await context.perform {
                updater(viewModel, current)
            }
        } else {
            addNewCoreData(id: uuid, model: viewModel, updater: updater)
        }
    }

    func save() async throws {
        await context.perform {
            saveCoreData()
        }
    }
}

// MARK: - Core Data Background Task

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

extension Logger {
    static let coreDataController = Logger(subsystem: subsystem, category: "CoreDataController")
}
