// @copyright André Trettin

import Foundation
import CoreData
import Observation

public protocol CoreDataPersistable: Sendable {
    associatedtype DataType: NSManagedObject & CoreDataId
    associatedtype Model: ModelType
    
    var dataController: CoreDataController<Model, DataType> { get }
    var token: String { get }
    
    func fetchIds() async throws -> [UUID]
    func delete(id: UUID) async throws
    func replace(id: UUID, with viewModel: Model, updater: @escaping @Sendable (Model, DataType) -> Void) async throws
    func save() async throws
    func flushPendingOperations() async throws
    
    @Sendable func mapViewModel(_ model: DataType, token: String) -> Model
    @Sendable func mapModel(_ viewModel: Model, into model: DataType)
}

public extension CoreDataPersistable {
    func replaceSync(id: UUID, with viewModel: any ModelType) throws {
        guard let viewModel = viewModel as? Model else { return }
        // Enqueue synchronously — an unstructured Task gives no ordering guarantee
        // between rapid edits to the same id and can lose the edit to a racing save().
        dataController.queueReplace(uuid: id, with: viewModel, updater: mapModel(_:into:))
    }

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
    
    func fetchIds() async throws -> [UUID] {
        try await dataController.fetchIds()
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

    func batchDelete(ids: [UUID]) async throws {
        try await dataController.batchDelete(uuids: ids)
    }

    func replace(id: UUID, with viewModel: Model, updater: @escaping @Sendable (Model, DataType) -> Void) async throws {
        try await dataController.replace(uuid: id, with: viewModel, updater: updater)
    }

    func save() async throws {
        try await dataController.save()
    }

    func flushPendingOperations() async throws {
        try await dataController.flushPendingOperations()
    }
}
