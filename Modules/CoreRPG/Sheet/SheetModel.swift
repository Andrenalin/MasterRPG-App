// @copyright André Trettin

import Foundation

@MainActor @Observable
public final class SheetModel: Identifiable, Sendable, Equatable, Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public init(id: UUID = UUID(), source: ItemRowModel, destination: ItemRowModel? = nil, linkNumber: Int? = nil, level: Int = 0, type: SheetModelType = .item, isShown: Bool = true, isFolded: Bool = false, canAdd: Bool = true, editType: SheetModelEditType = .none, showHeader: Bool = true, name: String, description: String, inlineEntries: [SheetModel] = [], entries: [SheetModel]) {
        self.id = id
        self.source = source
        self.destination = destination ?? source
        self.linkNumber = linkNumber
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

    /// Stable identity for this occurrence in a sheet tree.
    ///
    /// Domain identifiers are deliberately not used: the same item can appear in
    /// multiple branches, while mutable sources such as inline media can change
    /// without replacing the occurrence.
    public let id: UUID
    
    public var source: ItemRowModel
    public var destination: ItemRowModel
    /// The occurrence number from the source markdown link, when this sheet was
    /// materialized from linked text.
    public var linkNumber: Int?
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

    // MARK: - AI streaming generation
    public var aiPreviewEntry: SheetModel?
    public var aiGeneratedEntries: [SheetModel] = []

    // MARK: Generated answer preview
    public var isGeneratedAnswer: Bool = false
    public var isGeneratedSelected: Bool = false
    public var isGeneratedAccepted: Bool = false
    public var isGeneratedHidden: Bool = false
    public var generatedBatchId: String?

    // MARK: Selection
    /// Exclusive row selection across the SheetModel tree, managed by SheetRootModel.setSelected(_:parent:).
    /// Drives the selection border and feeds the FocusedValues-based menu-bar wiring.
    /// Distinct from `isGeneratedAnswer`/`isGeneratedSelected` — do not conflate.
    public var isSelected: Bool = false

    // MARK: Import review
    /// Entry-version review is intentionally independent from normal row selection and
    /// generated-answer selection. It is populated only for structured import sheets.
    var entryReviewModel: SheetEntryReviewModel?
    var isReviewPlaceholder: Bool = false

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
            let result = name.localizedStandardContains(searchText) || description.localizedStandardContains(searchText)
            isHidden = !result && !hasResult

            // If any child matches, expand this entry to show the matching child
            if hasResult {
                isShown = true
            }
        }
        return !isHidden
    }
    
    public static var empty: SheetModel {
        SheetModel(source: .empty, level: 0, name: "", description: "", entries: [])
    }
    
    public static func == (lhs: SheetModel, rhs: SheetModel) -> Bool {
        lhs.id == rhs.id
    }
}

public enum SheetModelEditType: Equatable, Hashable, Sendable, CaseIterable, Identifiable {
    case none
    case number
    case decimal
    case selection
    case text

    public var id: Self { self }
    
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

    var localizedTitle: LocalizedStringResource {
        switch self {
        case .text: LocalizedStringResource("Text", bundle: .module)
        case .number: LocalizedStringResource("Number", bundle: .module)
        case .decimal: LocalizedStringResource("Decimal", bundle: .module)
        case .selection: LocalizedStringResource("Selection", bundle: .module)
        case .none: LocalizedStringResource("None", bundle: .module)
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

public enum SheetInsertionPosition: Equatable, Hashable, Sendable {
    case end
    case after(UUID)
}

public extension SheetModel {
    var hasGenerationContent: Bool {
        guard !isGeneratedAnswer else { return false }
        return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
