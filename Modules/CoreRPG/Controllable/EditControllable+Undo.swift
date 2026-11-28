// @copyright André Trettin

import SwiftUI

// MARK: - Undo / Redo

/// Undo and redo apply a step's changes as deltas: each change reverts (or re-applies) only what
/// that edit changed, by a three-way merge onto the item as it is now, written to where the edit
/// was written. A sync merge or game change made since stays. A step from another game
/// generation is dropped instead of applied: its scope would now write into the library what was
/// written to game memory, or the other way round. The file is never undone: the file a step
/// referenced was deleted or moved. See CODE_AUDIT_Edit_Save §5.1-§5.7.
public extension EditControllable {
    @MainActor
    var canUndo: Bool {
        editorModel.undoManaged.nextUndoStep?.gameGeneration == itemControllable.itemDataModel.gameGeneration
    }

    @MainActor
    var canRedo: Bool {
        editorModel.undoManaged.nextRedoStep?.gameGeneration == itemControllable.itemDataModel.gameGeneration
    }

    @MainActor
    func undo() {
        guard let step = editorModel.undoManaged.nextUndoStep else { return }
        guard step.gameGeneration == itemControllable.itemDataModel.gameGeneration else {
            editorModel.undoManaged.removeAll()
            return
        }
        _ = editorModel.undoManaged.undo()
        for change in step.changes.reversed() {
            guard let before = change.before as? Model, let after = change.after as? Model else { continue }
            apply(change, from: after, to: before)
        }
    }

    @MainActor
    func redo() {
        guard let step = editorModel.undoManaged.nextRedoStep else { return }
        guard step.gameGeneration == itemControllable.itemDataModel.gameGeneration else {
            editorModel.undoManaged.removeAll()
            return
        }
        _ = editorModel.undoManaged.redo()
        for change in step.changes {
            guard let before = change.before as? Model, let after = change.after as? Model else { continue }
            apply(change, from: before, to: after)
        }
    }

    /// Writes what `base` → `target` changes onto the item, where the change was written. An item
    /// that is gone is skipped: undo used to insert it again. See CODE_AUDIT_Edit_Save §5.4.
    @MainActor
    private func apply(_ change: ItemEditUndoStep.Change, from base: Model, to target: Model) {
        switch change.scope {
        case .library:
            // A folder edit made on the library goes back to the library, also during a game.
            // See CODE_AUDIT_21 §5.31.
            guard var library = itemControllable.itemSync(for: change.itemId, noGame: true)?.copy() as? Model else { return }
            library.applyEdit(from: base, to: target, includingSessionContent: true, includingFile: false)
            itemControllable.persistMembershipChange(model: library)
        case .forced:
            applyForced(itemId: change.itemId, from: base, to: target)
        case .current:
            guard var current = editModel(for: change.itemId) else { return }
            current.applyEdit(from: base, to: target, includingSessionContent: true, includingFile: false)
            // The same register and tag count steps as a save, before the stored value is replaced.
            // Not for a memory-only game write. See CODE_AUDIT_29 §5.3.
            if persistsEdit(forceSave: false) {
                updateLinkRegister(to: current)
                updateTagCounts(to: current)
            }
            itemControllable.replace(model: current, isInsert: false, forceSave: false)
        }
        editorModel.cacheItemListModel.reset(itemId: change.itemId)
    }

    /// A step the editor saved with `forceSave` (the editor window during a game) is undone like
    /// it was saved: into the library and the game copy. The library gets the change without
    /// the game's session state; the game copy gets all of it. See CODE_AUDIT_Edit_Save §5.7.
    @MainActor
    private func applyForced(itemId: UUID, from base: Model, to target: Model) {
        guard let stored = itemControllable.itemSync(for: itemId, noGame: true) as? Model else { return }
        let gameValue = gameCopy(of: itemId)?.copy()
        var library = stored.copy()
        // Outside a game the library is where the whole edit was written.
        library.applyEdit(from: base, to: target, includingSessionContent: !itemControllable.itemDataModel.isGameMode, includingFile: false)
        updateLinkRegister(to: library, from: stored)
        updateTagCounts(to: library, from: stored)
        itemControllable.replace(model: library, isInsert: false, forceSave: true, syncGameMemory: false)
        if var gameValue {
            gameValue.applyEdit(from: base, to: target, includingSessionContent: true, includingFile: false)
            itemControllable.replaceInGameMemory(model: gameValue)
        }
    }

    @MainActor
    var undoTitle: String {
        canUndo ? editorModel.undoManaged.undoTitles.last ?? "" : ""
    }

    @MainActor
    var redoTitle: String {
        canRedo ? editorModel.undoManaged.redoTitles.last ?? "" : ""
    }
}
