// @copyright André Trettin

import SwiftUI
#if os(macOS)
import AppKit
#endif

#if !os(tvOS)
/// The Edit menu's Delete: the selected item, or the checked items in selection mode. The list
/// (`ListRootView`, `triggerDelete`) removes them and asks for confirmation.
struct DeleteItemButton: View {
    let root: any ItemRootControllable

    var body: some View {
        let listModel = root.folderListControllable.listModel
        let isSelectionMode = root.folderListControllable.listDisplayModel.isSelectionMode
        let rowIds = ModuleMenuPolicy.deleteRowIds(
            isSelectionMode: isSelectionMode,
            selection: listModel.selection,
            selected: listModel.selected
        )
        Button(role: .destructive) {
            guard !TextFieldShortcutForwarding.forwardDeleteToBeginningOfLine() else { return }
            root.navigationModel.triggerDelete = true
        } label: {
            Label {
                Text("Delete \(itemName(isSelectionMode: isSelectionMode))", bundle: .module)
            } icon: {
                Image(systemName: "trash")
            }
        }
        .keyboardShortcut(.delete, modifiers: .command)
        .disabled(!ModuleMenuPolicy.isDeleteEnabled(rowIds: rowIds))
    }

    /// "<name>", or "<name> and 2 more" for several checked items.
    private func itemName(isSelectionMode: Bool) -> String {
        if isSelectionMode {
            return root.menuController.itemName(currentSelected: nil)
        }
        guard let selectedItemId = root.currentSelectedItemId else { return "" }
        return root.menuController.itemName(currentSelected: selectedItemId)
    }
}

/// Command-Delete is "delete to start of line" in a text field. The menu's Delete is enabled
/// without the list having the focus, and a menu shortcut is handled before the field sees the
/// key, so the typed shortcut is handed back to the field.
enum TextFieldShortcutForwarding {
    /// Whether Command-Delete was typed in a text field and was sent to it instead. A click on
    /// the menu entry always deletes the items. On iOS the text field keeps the shortcut itself.
    @MainActor
    static func forwardDeleteToBeginningOfLine() -> Bool {
        #if os(macOS)
        guard NSApp.currentEvent?.type == .keyDown, NSApp.keyWindow?.firstResponder is NSText else { return false }
        return NSApp.sendAction(#selector(NSResponder.deleteToBeginningOfLine(_:)), to: nil, from: nil)
        #else
        return false
        #endif
    }
}

#Preview {
    DeleteItemButton(root: ItemRootController.fake)
}
#endif
