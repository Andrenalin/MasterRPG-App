// @copyright André Trettin

import Foundation
import SwiftUI

public protocol Storeable {
    var id: UUID { get }
}

actor FileDataModel<Datatype: Codable & Storeable & Sendable> {
    private(set) var data: [Datatype] = []

    func setData(update: [Datatype]) {
        data = update
    }

    func appendData(_ update: Datatype) {
        data.append(update)
    }

    func remove(at index: Int) {
        data.remove(at: index)
    }

    func moveData(from: IndexSet, to: Int) {
        data.move(fromOffsets: from, toOffset: to)
    }

    func update(data: Datatype, at index: Int) {
        self.data[index] = data
    }
}

public struct FileDataController<Datatype: Codable & Storeable & Sendable>: Sendable {
    private let model: FileDataModel<Datatype>
    private let persistence: FilePersistenceController
    private let priority: TaskPriority

    public init(name: String, type: FilePersistenceType = .store, dataExtension: String? = nil, priority: TaskPriority = .userInitiated) {
        persistence = FilePersistenceController(name: name, persistence: type, dataExtension: dataExtension, priority: priority)
        model = FileDataModel()
        self.priority = priority
    }
}

// MARK: - Fetch / store data

public extension FileDataController {
    func fetch() async {
        let persistenceLoader = persistence
        let backgroundTask = Task.detached(priority: priority) {
            let decoder = JSONDecoder()
            let jsonData = await persistenceLoader.load()
            let data = jsonData.compactMap { entry in
                if let restoreData = try? decoder.decode(Datatype.self, from: entry.data) {
                    return restoreData
                }
                return nil
            }
            return data
        }
        await model.setData(update: await backgroundTask.value)
    }

    func save() async {
        let encoder = JSONEncoder()
        let mappedData = await model.data.compactMap { entry -> DataModel? in
            if let encodedData = try? encoder.encode(entry) {
                return DataModel(id: entry.id, data: encodedData)
            }
            return nil
        }
        await persistence.save(data: mappedData)
    }
}

// MARK: - External data files

public extension FileDataController {
    func fetchData(for uuid: String) async throws -> Data? {
        try await persistence.loadData(for: uuid)
    }


    func saveData(_ data: Data, for dataModel: Datatype) async throws {
        try await persistence.saveData(data, for: dataModel.id.uuidString)
    }
}

// MARK: - Read

public extension FileDataController {
    func read(id: UUID) async -> Datatype? {
        await model.data.first(where: { $0.id == id })
    }
}

// MARK: - Modify data

public extension FileDataController {
    func addNew(data: Datatype) async {
        await model.appendData(data)
    }

    func delete(data: Datatype) async throws {
        try await delete(id: data.id)
    }

    func delete(id: UUID) async throws {
        guard let index = await model.data.firstIndex(where: { $0.id == id }) else { return }
        try await persistence.removeData(for: id.uuidString)
        await model.remove(at: index)
    }

    func moveData(from: IndexSet, to: Int) async  {
        await model.moveData(from: from, to: to)
    }

    func replace(data: Datatype) async {
        guard let index = await model.data.firstIndex(where: { $0.id == data.id }) else {
            await addNew(data: data)
            return
        }
        await model.update(data: data, at: index)
    }
}
