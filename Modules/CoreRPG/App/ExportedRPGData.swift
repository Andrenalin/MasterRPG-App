// @copyright André Trettin

import SwiftUI
import UniformTypeIdentifiers

public struct ItemModuleIds: Sendable, Equatable, Hashable {
    public init(dictionary: [NetworkModules: [UUID]] = [:]) {
        self.ids = dictionary
    }

    public init(ids: Set<UUID>, module: NetworkModules) {
        self.ids = [module: Array(ids)]
    }

    public init(ids: [UUID], module: NetworkModules) {
        self.ids = [module: Array(Set(ids))]
    }

    public init(items: [ItemRowTreeModel]) {
        var itemModules = ItemModuleIds()
        NetworkModules.allCases.forEach { module in
            let ids = items.filter { $0.model.typeId == module }.map { $0.model.itemId }
            if !ids.isEmpty {
                itemModules.merge(ids: ids, for: module)
            }
        }
        self.ids = itemModules.ids
    }

    public var ids: [NetworkModules: [UUID]]

    public func extract(module: NetworkModules) -> ItemModuleIds {
        ItemModuleIds(ids: ids[module, default: []], module: module)
    }

    public mutating func merge(other: ItemModuleIds) {
        for key in other.ids.keys {
            merge(ids: other.ids[key, default: []], for: key)
        }
    }

    public mutating func merge(ids: [UUID], for key: NetworkModules) {
        var keyIds = Set(self.ids[key, default: []])
        keyIds.formUnion(ids)
        self.ids[key] = Array(keyIds)
    }

    public var count: Int {
        ids.keys.reduce(0) { $0 + (ids[$1]?.count ?? 0)}
    }
}

public struct ExportedRPGData: Sendable, Codable {
    public init(allData: [NetworkModules: String] = [:], seenIds: Set<UUID> = Set<UUID>()) {
        self.allData = allData
        self.seenIds = seenIds
    }

    public var allData: [NetworkModules: String] = [:]
    public var seenIds: Set<UUID> = []

    public mutating func merge(other: ExportedRPGData) {
        for key in other.allData.keys {
            merge(text: other.allData[key, default: ""], for: key)
        }
    }

    public mutating func merge(text: String, for key: NetworkModules) {
        var keyIds = allData[key, default: ""]
        keyIds.append(text)
        allData[key] = keyIds
    }

}

public extension ExportedRPGData {
    func encodeData() -> Data? {
        let encoder = JSONEncoder()
        return try? encoder.encode(self)
    }

    static func decodeData(of data: Data?) -> ExportedRPGData? {
        guard let data else { return nil }
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(ExportedRPGData.self, from: data)
        } catch {
            print("ExportRPGData error \(error)")
        }
        return nil
    }
}

public extension UTType {
    static let rpgDocument = UTType(
        exportedAs: "de.AndreTrettin.GameMaster.gmz")

    static let gmsDocument = UTType(
        exportedAs: "de.AndreTrettin.GameMaster.gms")
}

#if os(tvOS)

    public struct RPGJsonFile {
        public static let readableContentTypes = [UTType.rpgDocument]

        public var data: ExportedRPGData

        public init(initialData: ExportedRPGData = ExportedRPGData()) {
            data = initialData
        }
    }

#else

    public struct RPGJsonFile: FileDocument {
        public static let readableContentTypes = [UTType.rpgDocument]

        public var data: ExportedRPGData

        public init(initialData: ExportedRPGData = ExportedRPGData()) {
            data = initialData
        }

        public init(configuration: ReadConfiguration) throws {
            if let endcoded = configuration.file.regularFileContents, let dataLoaded = try? JSONDecoder().decode(ExportedRPGData.self, from: endcoded) {
                data = dataLoaded
            } else {
                data = ExportedRPGData()
            }
        }

        public func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
            let encoder = JSONEncoder()
            do {
                let encodedData = try encoder.encode(data)
                return FileWrapper(regularFileWithContents: encodedData)
            } catch {
                print(error.localizedDescription)
            }
            return FileWrapper(regularFileWithContents: Data())
        }
    }

#endif
