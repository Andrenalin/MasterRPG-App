// @copyright André Trettin

import Foundation

public struct SheetFirstModel: Equatable, Hashable, Identifiable, Sendable {
    public init(source: ItemRowModel, destination: ItemRowModel? = nil, level: Int = 0, type: SheetFirstModelType = .item, canAdd: Bool = true, editType: SheetFirstModelEditType = .none, showHeader: Bool = true, name: String, description: String, inlineEntries: [SheetFirstModel] = [], entries: [SheetFirstModel]) {
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
        
    public let sheetType: SheetFirstModelType
    public let canAdd: Bool
    public let editType: SheetFirstModelEditType
    public let showHeader: Bool
    public var name: String
    public var description: String
    
    public var inlineEntries: [SheetFirstModel]
    public var entries: [SheetFirstModel]
    
    public var sheetIds: [ItemRowModel]
    
    func filter(searchText: String) -> [SheetFirstModel] {
        guard !searchText.isEmpty else { return entries }
        return entries.filter { entry in
            entry.name.localizedCaseInsensitiveContains(searchText) || entry.description.localizedCaseInsensitiveContains(searchText) || !entry.filter(searchText: searchText).isEmpty
        }
    }
    
    public static var empty: SheetFirstModel {
        SheetFirstModel(source: .empty, level: 0, name: "", description: "", entries: [])
    }
}

public enum SheetFirstModelEditType: Equatable, Hashable, Sendable {
    case none
    case number
    case decimal
    case selection
    case text
    
    var isEditable: Bool {
        self != .none
    }
}

public enum SheetFirstModelType: Equatable, Hashable, Sendable {
    case group
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
