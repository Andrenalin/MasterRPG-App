// @copyright André Trettin

import Foundation

public struct SheetModel: Equatable, Hashable, Identifiable, Sendable {
    public init(source: ItemRowModel, destination: ItemRowModel? = nil, level: Int = 0, type: SheetModelType = .item, canAdd: Bool = true, editType: SheetModelEditType = .none, showHeader: Bool = true, name: String, description: String, inlineEntries: [SheetModel] = [], entries: [SheetModel]) {
        self.id = "\(level)!\(source.entryId ?? source.itemId)"
        self.source = source
        self.destination = destination ?? source
        self.level = level
        self.sheetType = type
        self.canAdd = canAdd
        self.editType = editType
        self.showHeader = showHeader
        self.name = name
        self.description = description
        self.inlineEntries = inlineEntries
        self.entries = entries
        self.sheetIds = []
    }

    public let id: String
    public let source: ItemRowModel
    public let level: Int
    
    public let destination: ItemRowModel
    
    public let sheetType: SheetModelType
    public let canAdd: Bool
    public let editType: SheetModelEditType
    public let showHeader: Bool
    public let name: String
    public let description: String
    
    public var inlineEntries: [SheetModel]
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

public enum SheetModelEditType: Equatable, Hashable, Sendable {
    case none
    case number
    case decimal
    case selection
    case text
    
    var isEditable: Bool {
        self != .none
    }
}

public enum SheetModelType: Equatable, Hashable, Sendable {
    case item
    case edit
    case audioInline
    case dice
    case pdf
    case photo
    case photoInline
    case weather
    case space
}
