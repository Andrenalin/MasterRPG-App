// @copyright André Trettin

import Foundation
import SwiftUI

@MainActor @Observable
public final class ItemEditorModel: Sendable {
    public init(sheetEditorModel: SheetEditorModel) {
        self.sheetEditorModel = sheetEditorModel
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

    /// The undo history of every item edited in this module. Each step carries its own write
    /// scope and game generation (`ItemEditUndoStep`), so no side table can lose track of it.
    /// See CODE_AUDIT_Edit_Save §5.6.
    @ObservationIgnored public let undoManaged = UndoManaged<ItemEditUndoStep>()

    /// Called with the item id after an edit during a game that persisted (forced, or written to
    /// the library). The game installs it for its own length: a player announces an edited
    /// Character again, which only the inline editor's `.valueUpdate` did before. Never captures
    /// a view. See CODE_AUDIT_Edit_Save §5.24.
    @ObservationIgnored public var persistedGameEditHandler: (@MainActor (UUID) -> Void)?

    /// The item the editor shows. Selecting another item starts a new undo history.
    @ObservationIgnored public private(set) var currentItemId: UUID?

    func setCurrentItemId(_ itemId: UUID?) {
        currentItemId = itemId
    }

    /// Open `beginUndoGroup` calls: while one is open, every saved change joins one step.
    @ObservationIgnored private var undoGroupDepth = 0
    @ObservationIgnored private var undoGroupTitle: String?
    @ObservationIgnored private var undoGroupHasStep = false

    /// Starts one undo step for a user action that saves several times (move an entry between
    /// items, convert to group, ...). Nested groups join the outer one. See CODE_AUDIT_Edit_Save §5.5.
    public func beginUndoGroup(title: String) {
        if undoGroupDepth == 0 {
            undoGroupTitle = title
            undoGroupHasStep = false
        }
        undoGroupDepth += 1
    }

    public func endUndoGroup() {
        undoGroupDepth = max(0, undoGroupDepth - 1)
        if undoGroupDepth == 0 {
            undoGroupTitle = nil
            undoGroupHasStep = false
        }
    }

    /// Records one saved change, as a step of its own or as part of the open group. Steps of an
    /// earlier game generation are dropped first: they can never be applied again.
    func recordUndo(_ change: ItemEditUndoStep.Change, title: String, gameGeneration: Int) {
        if undoManaged.nextUndoStep.map({ $0.gameGeneration != gameGeneration }) == true
            || undoManaged.nextRedoStep.map({ $0.gameGeneration != gameGeneration }) == true {
            undoManaged.removeAll()
            undoGroupHasStep = false
        }
        if undoGroupDepth > 0, undoGroupHasStep, var step = undoManaged.nextUndoStep {
            step.changes.append(change)
            undoManaged.replaceLast(with: step)
            return
        }
        undoManaged.record(ItemEditUndoStep(changes: [change], gameGeneration: gameGeneration), title: undoGroupTitle ?? title)
        if undoGroupDepth > 0 {
            undoGroupHasStep = true
        }
    }

    /// Drops the changes of a deleted item; a step left without changes goes. Undo would have
    /// inserted the item again. See CODE_AUDIT_Edit_Save §5.4.
    func removeUndoChanges(of itemId: UUID) {
        undoManaged.compactMapSteps { step in
            var step = step
            step.changes.removeAll { $0.itemId == itemId }
            return step.changes.isEmpty ? nil : step
        }
    }

    /// The running duplicate started from any menu of this module. A second Duplicate press
    /// while it runs is ignored. See CODE_AUDIT_Folder §3.18.
    @ObservationIgnored var duplicateTask: Task<Void, Never>?

    /// The last queued file operation per item. Each new move or replacement of an item's file
    /// waits for the previous one, so two operations on one file never interleave.
    /// See CODE_AUDIT_Folder §3.8, §3.19.
    @ObservationIgnored var fileOperationTails: [UUID: (token: UUID, task: Task<Void, Never>)] = [:]
}
