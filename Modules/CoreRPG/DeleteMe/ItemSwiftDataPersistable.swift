// @copyright André Trettin

import Foundation
import CoreData

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
}

public extension ItemSwiftDataPersistable where DataType: Sendable {
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
