// @copyright André Trettin

import Foundation

public struct SheetModel: Equatable, Hashable, Identifiable, Sendable {
    public init(source: ItemRowModel, level: Int = 0, type: SheetModelType = .item, showHeader: Bool = true, name: String, description: String, entries: [SheetModel]) {
        self.id = "\(level)!\(source.entryId ?? source.itemId)"
        self.source = source
        self.level = level
        self.sheetType = type
        self.showHeader = showHeader
        self.name = name
        self.description = description
        self.entries = entries
        self.sheetIds = []
    }

    public let id: String
    public let source: ItemRowModel
    public let level: Int
    
    public let sheetType: SheetModelType
    public let showHeader: Bool
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

public enum SheetModelType: Equatable, Hashable, Sendable {
    case item
    case dice
    case photo
    case weather
}
