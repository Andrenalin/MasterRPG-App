// @copyright André Trettin

import SwiftUI

/// While a text input inside the modified view has the focus, Undo and Redo in the menu (Cmd+Z,
/// Shift+Cmd+Z) go to the window's undo manager, which holds the typing, instead of undoing the
/// module's last saved edit (possibly of another item), which via the editor's reload also
/// wiped the typing. See CODE_AUDIT_Edit_Save §8.2.
///
/// `UndoManager.canUndo` is not observable, so the menu items stay enabled while editing; with
/// nothing typed to undo they do nothing.
private struct TextInputUndoModifier: ViewModifier {
    @Environment(\.undoManager) private var undoManager

    func body(content: Content) -> some View {
#if os(tvOS)
        content
#else
        content.focusedValue(\.editorUndoActions, undoManager.map { manager in
            FocusedUndoActions(
                canUndo: true,
                canRedo: true,
                undoTitle: manager.undoActionName,
                redoTitle: manager.redoActionName,
                undo: { manager.undo() },
                redo: { manager.redo() }
            )
        })
#endif
    }
}

public extension View {
    /// Routes the menu's Undo and Redo to the typing while a text input inside has the focus.
    func textInputUndo() -> some View {
        modifier(TextInputUndoModifier())
    }
}
