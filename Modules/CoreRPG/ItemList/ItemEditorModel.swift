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

    /// The running duplicate started from any menu of this module. A second Duplicate press
    /// while it runs is ignored. See CODE_AUDIT_Folder §3.18.
    @ObservationIgnored var duplicateTask: Task<Void, Never>?

    /// The last queued file operation per item. Each new move or replacement of an item's file
    /// waits for the previous one, so two operations on one file never interleave.
    /// See CODE_AUDIT_Folder §3.8, §3.19.
    @ObservationIgnored var fileOperationTails: [UUID: (token: UUID, task: Task<Void, Never>)] = [:]
}
