// @copyright André Trettin

import Foundation
import CoreData
import Observation
import SwiftData

public protocol DataPersistenceControllable: Sendable {
    func fetch(id: UUID) async throws -> ModelType?
    func delete(id: UUID) async throws
    func replace(id: UUID, with viewModel: any ModelType) async throws
    func save() async throws
}

public protocol CoreDataPersistable: Sendable {
    associatedtype DataType: NSManagedObject & CoreDataId
    associatedtype Model: ModelType
    
    var dataController: CoreDataController<Model, DataType> { get }
    var itemControllable: any ItemControllable { get }
    var token: String { get }
    
    func delete(id: UUID) async throws
    func replace(id: UUID, with viewModel: Model, updater: @escaping @Sendable (Model, DataType) -> Void) async throws
    func save() async throws
    
    @Sendable func mapViewModel(_ model: DataType, token: String) -> Model
    @Sendable func mapModel(_ viewModel: Model, into model: DataType)
}

public extension CoreDataPersistable {
    func replace(id: UUID, with viewModel: any ModelType) async throws {
        guard let viewModel = viewModel as? Model else { return }
        try await replace(id: id, with: viewModel, updater: mapModel(_:into:))
    }

    func tags(from model: String?) -> [String] {
        guard let model else { return [] }
        return model.components(separatedBy: ",").compactMap {
            let tag = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            if tag.isEmpty {
                return nil
            }
            return tag
        }
    }
    
    func fetch() async throws -> [Model] {
        try await dataController.fetch {
            mapViewModel($0, token: token)
        }
    }
    
    func fetch(id: UUID) async throws -> ModelType? {
        try await dataController.fetch(uuid: id) {
            mapViewModel($0, token: token)
        }
    }

    func delete(id: UUID) async throws {
        try await dataController.delete(uuid: id)
    }

    func replace(id: UUID, with viewModel: Model, updater: @escaping @Sendable (Model, DataType) -> Void) async throws {
        try await dataController.replace(uuid: id, with: viewModel, updater: updater)
    }

    func save() async throws {
        try await dataController.save()
    }
}

// MARK: Core Data --> CloudKit Sync

public extension CoreDataPersistable {
    func start() {
        Task.detached(priority: .userInitiated) {
            await fetchUpdates()
        }
    }
    
    @Sendable
    func updateFromSync(deletedIds: [UUID], insertedIds: [UUID], updatedIds: [UUID]) {
        Task.detached(priority: .userInitiated) {
            if !deletedIds.isEmpty {
                let ids = try await dataController.fetchIds()
                let removedIds = await Set(itemControllable.itemDataModel.items).subtracting(ids)
                for removedId in removedIds {
                    await itemControllable.delete(itemId: removedId)
                }
            }
            for insertedId in insertedIds {
                guard let model = try await dataController.fetch(uuid: insertedId, mapper: {
                    mapViewModel($0, token: token) }) else { continue }
                await itemControllable.update(model: model)
            }
            for updatedId in updatedIds {
                guard let model = try await dataController.fetch(uuid: updatedId, mapper: { mapViewModel($0, token: token) }) else { continue }
                await itemControllable.update(model: model)
                await itemControllable.didUpdate(model: model)
            }
        }
    }
    
    func fetchUpdates() async {
        guard let newItems = try? await fetch() else { return }
        Task { @MainActor in
            await itemControllable.updates(newItems)
        }
    }
}

public protocol ItemSwiftDataPersistable: Sendable {
    associatedtype DataType: SwiftDataType
    associatedtype Model: ModelType
    
    var swiftDataController: SwiftDataController<Model, DataType> { get }
    
    func delete(id: UUID) async throws
    func replace(id: UUID, with viewModel: Model, mapper: @escaping @Sendable (Model) -> DataType, updater: @escaping @Sendable (Model, DataType) -> Void) async throws
    func save() async throws
    
    @Sendable func mapViewModel(_ model: DataType, token: String) -> Model
    @Sendable func mapModel(_ viewModel: Model) -> DataType
    @Sendable func mapModel(_ viewModel: Model, into model: DataType)
}

public extension ItemSwiftDataPersistable {
    func replace(id: UUID, with viewModel: any ModelType) async throws {
        guard let viewModel = viewModel as? Model else { return }
        try await replace(id: id, with: viewModel, mapper: mapModel(_:), updater: mapModel(_:into:))
    }

    func tags(from model: String?) -> [String] {
        guard let model else { return [] }
        return model.components(separatedBy: ",").compactMap {
            let tag = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            if tag.isEmpty {
                return nil
            }
            return tag
        }
    }
    
    func fetch() async throws -> [DataType] {
        try await swiftDataController.fetch()
    }
        
    func add(data: DataType) async {
        await swiftDataController.add(data: data)
    }

    func delete(id: UUID) async throws {
        try await swiftDataController.delete(uuid: id)
    }

    func replace(id: UUID, with viewModel: Model, mapper: @escaping @Sendable (Model) -> DataType, updater: @escaping @Sendable (Model, DataType) -> Void) async throws {
        try await swiftDataController.replace(uuid: id, with: viewModel, mapper: mapper, updater: updater)
    }

    func save() async throws {
        try await swiftDataController.save()
    }

}
