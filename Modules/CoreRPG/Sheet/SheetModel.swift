// @copyright André Trettin

import Foundation

public struct SheetModel: Equatable, Hashable, Identifiable, Sendable {
    public init(id: UUID, name: String = "", description: String = "", groups: [SheetGroupModel] = []) {
        self.id = id
        self.name = name
        self.description = description
        self.groups = groups
    }

    public let id: UUID
    public let name: String
    public let description: String

    public var groups: [SheetGroupModel]

    func filteredGroups(for searchText: String) -> [SheetGroupModel] {
        guard !searchText.isEmpty else { return groups }
        return groups.filter { group in
            group.name.localizedCaseInsensitiveContains(searchText) || group.description.localizedCaseInsensitiveContains(searchText) ||
            !group.filteredEntries(for: searchText).isEmpty
        }
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

