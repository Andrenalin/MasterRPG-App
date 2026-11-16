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
        // Undoing a folder edit made on the library: what redo brings back is the library's
        // state now, and it is a library edit as well. See CODE_AUDIT_21 §5.31.
        if let next = editorModel.undoManaged.nextUndoValue as? Model, editorModel.isLibraryScopedUndo(next),
           let current = itemControllable.itemSync(for: next.id, noGame: true)?.copy() {
            editorModel.markLibraryScopedUndo(current)
            editorModel.undoManaged.updateValue(current)
        }
        editorModel.undoManaged.undo()
        applyUndoValue()
    }

    @MainActor
    func redo() {
        if let next = editorModel.undoManaged.nextRedoValue as? Model, editorModel.isLibraryScopedUndo(next),
           let current = itemControllable.itemSync(for: next.id, noGame: true)?.copy() {
            editorModel.markLibraryScopedUndo(current)
            editorModel.undoManaged.updateValue(current)
        }
        editorModel.undoManaged.redo()
        applyUndoValue()
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
