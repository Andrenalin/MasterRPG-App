// @copyright André Trettin

import Foundation

@MainActor @Observable
public final class SheetModel: Identifiable, Sendable {
    public init(source: ItemRowModel, destination: ItemRowModel? = nil, level: Int = 0, type: SheetModelType = .item, isShown: Bool = true, isFolded: Bool = false, canAdd: Bool = true, editType: SheetModelEditType = .none, showHeader: Bool = true, name: String, description: String, inlineEntries: [SheetModel] = [], entries: [SheetModel]) {
        self.id = UUID()
        self.source = source
        self.destination = destination ?? source
        self.level = level
        self.sheetType = type
        self.isShown = isShown
        self.isFolded = isFolded
        self.name = name
        self.description = description
        self.inlineEntries = inlineEntries
        self.entries = entries

        self.canAdd = canAdd
        self.editType = editType
        self.showHeader = showHeader
    }

    public let id: UUID
    public let source: ItemRowModel
    public let destination: ItemRowModel
    public let level: Int

    public let sheetType: SheetModelType
    public var isShown: Bool
    public var lastIsShown: Bool = false
    public var isHidden: Bool = false
    public var isFolded: Bool = false
    
    public var name: String
    public var description: String
            
    public var inlineEntries: [SheetModel]
    public var entries: [SheetModel]
        
    // MARK: Editor
    public let editType: SheetModelEditType
    public var isEditing: Bool = false
    
    public let canAdd: Bool
    public let showHeader: Bool

    var content: String {
        if description.isEmpty {
            name
        } else if name.isEmpty {
            description
        } else {
            "**" + name + "**: " + description
        }
    }

    func filter(searchText: String) -> Bool {
        var hasResult: Bool = false
        entries.forEach {
            let subResult = $0.filter(searchText: searchText)
            hasResult = hasResult || subResult
        }
        if searchText.isEmpty {
            isHidden <=> false
            isShown <=> lastIsShown
        } else {
            let result = name.localizedCaseInsensitiveContains(searchText) || description.localizedCaseInsensitiveContains(searchText)
            if hasResult {
                isShown <=> true
            }
            isHidden <=> !result && !hasResult
        }
        return !isHidden
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
extension SheetModel: InlineEditorEntry {
    // Already has source and editType properties
}

