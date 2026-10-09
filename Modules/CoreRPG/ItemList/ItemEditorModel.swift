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

    /// The sheet that opened the link picker for one of this module's entries, and that
    /// entry. The picker (`EditorLinkView`) writes the links straight through the edit
    /// controller, so the sheet showing the entry never sees the change on its own. It is
    /// not necessarily this module's `sheetRootModel`: a linked item's entries are also
    /// shown nested in another module's sheet, which is why the opener registers itself.
    @ObservationIgnored private weak var linkSelectionSheetRootModel: SheetRootModel?
    @ObservationIgnored private var linkSelectionSource: ItemRowModel?

    func beginLinkSelection(for source: ItemRowModel, in sheetRootModel: SheetRootModel) {
        linkSelectionSource = source
        linkSelectionSheetRootModel = sheetRootModel
    }

    /// Reconciles the sheet registered by `beginLinkSelection(for:in:)` once the picker
    /// added its links. A picker opened for another entry (e.g. from the entry editor)
    /// leaves the registration alone.
    func finishLinkSelection(itemId: UUID, entryId: UUID) {
        guard let source = linkSelectionSource, source.itemId == itemId, source.entryId == entryId else { return }
        linkSelectionSheetRootModel?.updateAfterLinkSelection(source: source)
        linkSelectionSource = nil
        linkSelectionSheetRootModel = nil
    }

    @ObservationIgnored public var undoManaged: UndoManaged<ModelType?>

    /// The undo and redo values that belong to a folder edit made on the library, not on what
    /// is being edited: restoring one writes the library, also during a game. The newest are
    /// kept; an undo stack is not deeper. See CODE_AUDIT_21 §5.31.
    @ObservationIgnored private var libraryScopedUndoValues: [AnyObject] = []

    func markLibraryScopedUndo(_ value: ModelType) {
        libraryScopedUndoValues.append(value as AnyObject)
        if libraryScopedUndoValues.count > 64 {
            libraryScopedUndoValues.removeFirst(libraryScopedUndoValues.count - 64)
        }
    }

    func isLibraryScopedUndo(_ value: ModelType) -> Bool {
        let object = value as AnyObject
        return libraryScopedUndoValues.contains { $0 === object }
    }

    /// The running duplicate started from any menu of this module. A second Duplicate press
    /// while it runs is ignored. See CODE_AUDIT_Folder §3.18.
    @ObservationIgnored var duplicateTask: Task<Void, Never>?

    /// The last queued file operation per item. Each new move or replacement of an item's file
    /// waits for the previous one, so two operations on one file never interleave.
    /// See CODE_AUDIT_Folder §3.8, §3.19.
    @ObservationIgnored var fileOperationTails: [UUID: (token: UUID, task: Task<Void, Never>)] = [:]
}
