// @copyright André Trettin

import Foundation

public struct SheetModel: Equatable, Hashable, Identifiable, Sendable {
    public init(source: ItemRowModel, level: Int = 0, name: String, description: String, entries: [SheetModel]) {
        self.id = "\(level)!\(source.entryId ?? source.itemId)"
        self.source = source
        self.level = level
        self.name = name
        self.description = description
        self.entries = entries
        self.sheetIds = []
    }

    public let id: String
    public let source: ItemRowModel
    public let level: Int
    public let name: String
    public let description: String

    public var entries: [SheetModel]
    
    public var sheetIds: [ItemRowModel]
    
    func filter(searchText: String) -> [SheetModel] {
        guard !searchText.isEmpty else { return entries }
        return entries.filter { entry in
            entry.name.localizedCaseInsensitiveContains(searchText) || entry.description.localizedCaseInsensitiveContains(searchText) || !entry.filter(searchText: searchText).isEmpty
        }
    }
    
    public static var empty: SheetModel {
        SheetModel(source: .empty, level: 0, name: "", description: "", entries: [])
    }
}

public struct SheetGroupModel: Equatable, Hashable, Identifiable, Sendable {
    public init(id: UUID, name: String, description: String, level: Int = 0, entries: [SheetEntryModel]) {
        self.id = id
        self.name = name
        self.description = description
        self.level = level
        self.sheetIds = []
        self.entries = entries
    }
    
    public let id: UUID
    public let name: String
    public let description: String
    public let level: Int

    public var sheetIds: [UUID]
    public let entries: [SheetEntryModel]

    func filteredEntries(for searchText: String) -> [SheetEntryModel] {
        guard !searchText.isEmpty else { return entries }
        return entries.filter { entry in
            entry.name.localizedCaseInsensitiveContains(searchText) || entry.value.localizedCaseInsensitiveContains(searchText)
        }
    }

}

public struct SheetEntryModel: Equatable, Hashable, Identifiable, Sendable {
    public init(id: UUID, name: String, value: String) {
        self.id = id
        self.name = name
        self.value = value
    }
    
    public let id: UUID
    public let name: String
    public let value: String
}

