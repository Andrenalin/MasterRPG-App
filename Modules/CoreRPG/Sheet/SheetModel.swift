// @copyright André Trettin

import Foundation

@MainActor @Observable
public final class SheetModel: Identifiable, Sendable, Equatable, Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(source)
        hasher.combine(destination)
        hasher.combine(level)
        hasher.combine(sheetType)
    }
    
    public init(source: ItemRowModel, destination: ItemRowModel? = nil, level: Int = 0, type: SheetModelType = .item, isShown: Bool = true, isFolded: Bool = false, canAdd: Bool = true, editType: SheetModelEditType = .none, showHeader: Bool = true, name: String, description: String, inlineEntries: [SheetModel] = [], entries: [SheetModel]) {
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

    /// Computed ID based on source, destination, and type to ensure uniqueness and consistency
    /// This prevents duplicate ID issues when the same item/entry appears multiple times
    public var id: String {
        var components: [String] = []
        
        // Add source identifier
        components.append(source.itemId.uuidString)
        if let entryId = source.entryId {
            components.append(entryId.uuidString)
        }
        components.append(source.typeId.token)
        
        // Add destination if different from source
        if destination.itemId != source.itemId || destination.entryId != source.entryId {
            components.append("dest")
            components.append(destination.itemId.uuidString)
            if let destEntryId = destination.entryId {
                components.append(destEntryId.uuidString)
            }
        }
        
        // Add sheet type for inline entries (dice, photo, etc.)
        if sheetType != .item {
            components.append("type")
            components.append("\(sheetType)")
        }
        
        return components.joined(separator: "-")
    }
    
    public var source: ItemRowModel
    public var destination: ItemRowModel
    public var level: Int

    public var sheetType: SheetModelType
    public var isShown: Bool
    public var lastIsShown: Bool = false
    public var isHidden: Bool = false
    public var isFolded: Bool = false
    
    public var name: String
    public var description: String
            
    public var inlineEntries: [SheetModel]
    public var entries: [SheetModel]
        
    // MARK: Editor
    public var editType: SheetModelEditType
    public var isEditing: Bool = false
    public var hasChanged: Bool = false

    // MARK: Generated answer preview
    public var isGeneratedAnswer: Bool = false
    public var isGeneratedSelected: Bool = false
    public var isGeneratedAccepted: Bool = false
    public var isGeneratedHidden: Bool = false
    public var generatedBatchID: String?
    
    public var canAdd: Bool
    public var showHeader: Bool

    func filter(searchText: String, shouldRestoreState: Bool = false) -> Bool {
        var hasResult: Bool = false
        entries.forEach {
            let subResult = $0.filter(searchText: searchText, shouldRestoreState: shouldRestoreState)
            hasResult = hasResult || subResult
        }
        if searchText.isEmpty {
            isHidden = false
            // Only restore state when clearing an active search
            if shouldRestoreState {
                isShown = lastIsShown
            }
        } else {
            // During search: first restore to original state, then expand if needed
            // This ensures we start from the saved state for each search query change
            isShown = lastIsShown

            // Set isHidden based on match
            let result = name.localizedCaseInsensitiveContains(searchText) || description.localizedCaseInsensitiveContains(searchText)
            isHidden = !result && !hasResult

            // If any child matches, expand this entry to show the matching child
            if hasResult {
                isShown = true
            }
        }
        return !isHidden
    }
    
    func reset(with otherSheetModel: SheetModel) {
        source <=> otherSheetModel.source
        destination <=> otherSheetModel.destination
        level <=> otherSheetModel.level
        
        sheetType <=> otherSheetModel.sheetType
        isShown <=> otherSheetModel.isShown
        lastIsShown <=> otherSheetModel.lastIsShown
        isHidden <=> otherSheetModel.isHidden
        isFolded <=> otherSheetModel.isFolded
        
        name <=> otherSheetModel.name
        description <=> otherSheetModel.description
        inlineEntries <=> otherSheetModel.inlineEntries
        entries = otherSheetModel.entries
        
        editType <=> otherSheetModel.editType
        isEditing <=> otherSheetModel.isEditing
        hasChanged <=> otherSheetModel.hasChanged
        isGeneratedAnswer <=> otherSheetModel.isGeneratedAnswer
        isGeneratedSelected <=> otherSheetModel.isGeneratedSelected
        isGeneratedAccepted <=> otherSheetModel.isGeneratedAccepted
        isGeneratedHidden <=> otherSheetModel.isGeneratedHidden
        generatedBatchID <=> otherSheetModel.generatedBatchID
        
        canAdd <=> otherSheetModel.canAdd
        showHeader <=> otherSheetModel.showHeader
    }
    
    public static var empty: SheetModel {
        SheetModel(source: .empty, level: 0, name: "", description: "", entries: [])
    }
    
    public static func == (lhs: SheetModel, rhs: SheetModel) -> Bool {
        return lhs._source == rhs._source &&
        lhs._destination == rhs._destination &&
        lhs._level == rhs._level &&
        lhs._sheetType == rhs._sheetType &&
        lhs._isShown == rhs._isShown &&
        lhs._lastIsShown == rhs._lastIsShown &&
        lhs._isHidden == rhs._isHidden &&
        lhs._isFolded == rhs._isFolded &&
        lhs._name == rhs._name &&
        lhs._description == rhs._description &&
        lhs._inlineEntries == rhs._inlineEntries &&
        lhs._entries == rhs._entries &&
        lhs._editType == rhs._editType &&
        lhs._isEditing == rhs._isEditing &&
        lhs._hasChanged == rhs._hasChanged &&
        lhs._isGeneratedAnswer == rhs._isGeneratedAnswer &&
        lhs._isGeneratedSelected == rhs._isGeneratedSelected &&
        lhs._isGeneratedAccepted == rhs._isGeneratedAccepted &&
        lhs._isGeneratedHidden == rhs._isGeneratedHidden &&
        lhs._generatedBatchID == rhs._generatedBatchID &&
        lhs._canAdd == rhs._canAdd &&
        lhs._showHeader == rhs._showHeader
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
    
    var icon: String {
        switch self {
            case .text: "doc.text"
            case .number: "textformat.12"
            case .decimal: "number"
            case .selection: "checkmark.square"
            case .none: ""
        }
    }

}

public enum SheetModelType: Equatable, Hashable, Sendable {
    // general
    case item
    case group // only for character module to simulate folders

    // module specific
    case audio
    case dice
    case pdf
    case photo
    case space
    case weather
}
