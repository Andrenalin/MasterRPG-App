// @copyright André Trettin

import SwiftUI

// MARK: - Undo / Redo

public extension EditControllable {
    @MainActor
    var canUndo: Bool {
        editorModel.undoManaged.canUndo
    }

    @MainActor
    var canRedo: Bool {
        editorModel.undoManaged.canRedo
    }

    @MainActor
    func undo() {
        recordLiveValue(before: editorModel.undoManaged.nextUndoValue as? Model)
        editorModel.undoManaged.undo()
        applyUndoValue()
    }

    @MainActor
    func redo() {
        recordLiveValue(before: editorModel.undoManaged.nextRedoValue as? Model)
        editorModel.undoManaged.redo()
        applyUndoValue()
    }

    /// `UndoManaged.undo()`/`redo()` push their current `value` onto the opposite stack, and a
    /// save never advances `value`, so it is stale (the state from when the item was selected).
    /// Before moving, make it the item as it is now: that is what the opposite step must bring
    /// back, so edit, edit, undo, redo ends on the second edit instead of the original. The item
    /// to read is the one the step restores, as the stack holds the states of every item edited.
    /// An edit made on the library (a folder edit during a game) is a library edit again when it
    /// is undone: what redo brings back is the library's state now. See CODE_AUDIT §5.1 and
    /// CODE_AUDIT_21 §5.31.
    @MainActor
    private func recordLiveValue(before next: Model?) {
        guard let next else { return }
        if editorModel.isLibraryScopedUndo(next) {
            guard let current = itemControllable.itemSync(for: next.id, noGame: true)?.copy() else { return }
            editorModel.markLibraryScopedUndo(current)
            editorModel.undoManaged.updateValue(current)
        } else if let current = itemControllable.itemSync(for: next.id)?.copy() {
            editorModel.undoManaged.updateValue(current)
        }
    }

    /// Writes the value undo or redo just restored. A folder edit made on the library goes
    /// back to the library: through `replace` with its default it only reached game memory
    /// during a game, and the library kept the move. See CODE_AUDIT_21 §5.31.
    @MainActor
    private func applyUndoValue() {
        guard let model = editorModel.undoManaged.value as? Model else { return }
        if editorModel.isLibraryScopedUndo(model) {
            itemControllable.persistMembershipChange(model: model)
        } else {
            // The same register and tag count steps as a save, before the stored value is replaced.
            updateLinkRegister(to: model)
            updateTagCounts(to: model)
            itemControllable.replace(model: model, isInsert: false)
        }
        editorModel.cacheItemListModel.reset(itemId: model.id)
    }

    @MainActor
    var undoTitle: String {
        editorModel.undoManaged.undoTitles.last ?? ""
    }

    @MainActor
    var redoTitle: String {
        editorModel.undoManaged.redoTitles.last ?? ""
    }
}
