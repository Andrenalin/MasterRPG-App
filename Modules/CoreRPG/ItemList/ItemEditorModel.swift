// @copyright André Trettin

import Foundation
import SwiftUI

@MainActor @Observable
public final class ItemEditorModel: Sendable {
    public init(sheetEditorModel: SheetEditorModel) {
        self.sheetEditorModel = sheetEditorModel
        self.undoManaged = UndoManaged(initialValue: nil)
    }

    public var currentModel: ModelType? {
        undoManaged.value
    }

    public var hasChangedEntries: Int = 0

    public var deactivateEntryEditor: Bool = false
    
    public var cacheItemListModel: CacheItemListModel = CacheItemListModel()

    public var sheetRootModel: SheetRootModel?

    /// The live game view's persistent counterpart to `sheetRootModel` — reused
    /// across character selections the same way `sheetRootModel` is, instead of
    /// being rebuilt from scratch on every selection (`TableRootSheet` used to
    /// construct a throwaway `SheetRootModel` per item via `.id(model.id)`).
    /// Keeping one long-lived instance per side is what lets `SheetRootModel`
    /// tell its counterpart directly ("I just reconciled item X") in
    /// `syncCounterpart()` instead of needing a general registry.
    public var gameSheetRootModel: SheetRootModel?
    public let sheetEditorModel: SheetEditorModel

    
    @ObservationIgnored public var undoManaged: UndoManaged<ModelType?>

    func reset() {
        if undoManaged.value != nil {
            undoManaged.resetValue(nil)
        }
        cacheItemListModel.resetItemLink()
    }
}
