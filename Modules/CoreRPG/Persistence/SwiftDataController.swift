// @copyright André Trettin

import Combine
import os.log
import SwiftData
import SwiftUI

public protocol SwiftDataType: PersistentModel, Sendable {
    var uuid: UUID? { get }
}

@ModelActor
public actor SwiftDataController<Model: ModelType, DataType: SwiftDataType> {
    func fetch() async throws -> [DataType] {
        let descriptor = FetchDescriptor<DataType>(sortBy: [SortDescriptor(\.uuid)])
        return try modelContext.fetch(descriptor)
    }

    func fetch(uuid: UUID) async throws -> DataType? {
        let predicate = #Predicate<DataType> { $0.uuid == uuid }
        let descriptor = FetchDescriptor<DataType>(predicate: predicate)
        return try modelContext.fetch(descriptor).first
    }

    func add(data: DataType) async {
        modelContext.insert(data)
    }

    func delete(uuid: UUID) async throws {
        guard let model = try await fetch(uuid: uuid) else { return }
        modelContext.delete(model)
    }
    
    func delete(data: DataType) {
        modelContext.delete(data)
    }
    
    func save() async throws {
        try modelContext.save()
    }
    
    func replace(uuid: UUID, with viewModel: Model, mapper: @escaping @Sendable (Model) -> DataType, updater: @escaping @Sendable (Model, DataType) -> Void) async throws {
        if let current = try await fetch(uuid: uuid) {
            updater(viewModel, current)
        } else {
            await add(data: mapper(viewModel))
        }
    }
}

private extension Logger {
    static let swiftDataController = Logger(subsystem: subsystem, category: "SwiftDataController")
}
