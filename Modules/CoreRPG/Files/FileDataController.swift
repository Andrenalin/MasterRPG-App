// @copyright André Trettin

import Foundation
import SwiftUI

public protocol Storable {
    var id: UUID { get }
}

actor FileDataModel<Datatype: Codable & Storable & Sendable> {
    private(set) var data: [Datatype] = []
    /// Stored entries this build could not decode. They are written back unchanged, so a save
    /// never drops data a newer or different shape still owns. See CODE_AUDIT_23 §5.5.
    private(set) var undecodable: [DataModel] = []

    func setData(update: [Datatype], undecodable: [DataModel] = []) {
        data = update
        self.undecodable = undecodable
    }

    func appendData(_ update: Datatype) {
        data.append(update)
    }

    func moveData(from: IndexSet, to: Int) {
        data.move(fromOffsets: from, toOffset: to)
    }

    /// Atomic find-and-remove — unlike a separate `firstIndex(where:)` await
    /// followed by a separate `remove(at:)` await, no other actor call can
    /// interleave between the lookup and the mutation. See CODE_AUDIT §3.1.
    @discardableResult
    func removeIfPresent(id: UUID) -> Bool {
        guard let index = data.firstIndex(where: { $0.id == id }) else { return false }
        data.remove(at: index)
        return true
    }

    /// Atomic find-and-replace counterpart to `removeIfPresent(id:)`. Returns
    /// `false` when no existing entry matched, so the caller can fall back to
    /// inserting a new one. See CODE_AUDIT §3.1.
    @discardableResult
    func replaceIfPresent(_ newData: Datatype) -> Bool {
        guard let index = data.firstIndex(where: { $0.id == newData.id }) else { return false }
        data[index] = newData
        return true
    }
}

public struct FileDataController<Datatype: Codable & Storable & Sendable>: Sendable {
    private let model: FileDataModel<Datatype>
    private let persistence: FilePersistenceController

    /// The former `priority` parameter was stored but never used. See CODE_AUDIT_18 §7.4.
    public init(name: String, type: FilePersistenceType = .store, dataExtension: String? = nil) {
        persistence = FilePersistenceController(name: name, persistence: type, dataExtension: dataExtension)
        model = FileDataModel()
    }
}

// MARK: - Fetch / store data

public extension FileDataController {
    /// - Returns: `false` when the stored file exists but could not be read. Nothing is replaced
    ///   then, and the caller must not save over the file. See CODE_AUDIT_23 §5.5.
    @discardableResult
    func fetch() async -> Bool {
        let persistenceLoader = persistence
        let decoder = JSONCoding.decoder
        guard let jsonData = await persistenceLoader.loadIfReadable() else { return false }
        var data: [Datatype] = []
        var undecodable: [DataModel] = []
        for entry in jsonData {
            if let restoreData = try? decoder.decode(Datatype.self, from: entry.data) {
                data.append(restoreData)
            } else {
                undecodable.append(entry)
            }
        }
        await model.setData(update: data, undecodable: undecodable)
        return true
    }

    @discardableResult
    func save() async -> Bool {
        let encoder = JSONCoding.encoder
        let mappedData = await model.data.compactMap { entry -> DataModel? in
            if let encodedData = try? encoder.encode(entry) {
                return DataModel(id: entry.id, data: encodedData)
            }
            return nil
        }
        let writtenIds = Set(mappedData.map(\.id))
        let kept = await model.undecodable.filter { !writtenIds.contains($0.id) }
        return await persistence.save(data: mappedData + kept)
    }
}

// MARK: - External data files

public extension FileDataController {

    func saveData(_ data: Data, for dataModel: Datatype) async throws {
        try await persistence.saveData(data, for: dataModel.id.uuidString)
    }
}

// MARK: - Read

public extension FileDataController {
    func read(id: UUID) async -> Datatype? {
        await model.data.first(where: { $0.id == id })
    }

    /// Whether the store holds an entry with this id that this build could not decode. `read`
    /// returns `nil` for it as well, so a caller that saves must tell the two apart.
    /// See CODE_AUDIT_24 §5.12.
    func isUndecodable(id: UUID) async -> Bool {
        await model.undecodable.contains { $0.id == id }
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
        guard await model.removeIfPresent(id: id) else { return }
        try await persistence.removeData(for: id.uuidString)
    }

    func moveData(from: IndexSet, to: Int) async  {
        await model.moveData(from: from, to: to)
    }

    func replace(data: Datatype) async {
        guard await model.replaceIfPresent(data) else {
            await addNew(data: data)
            return
        }
    }
}
