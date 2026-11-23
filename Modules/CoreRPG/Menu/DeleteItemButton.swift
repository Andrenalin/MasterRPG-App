// @copyright André Trettin

import SwiftUI

#if !os(tvOS)
struct DeleteItemButton: View {
    let root: any ItemRootControllable
    var isListFocused = true

    var body: some View {
        Button(role: .destructive) {
            root.navigationModel.triggerDelete = true
        } label: {
            Label {
                Text("Delete \(item?.name ?? "")", bundle: .module)
            } icon: {
                Image(systemName: "trash")
            }
        }
        .keyboardShortcut(.delete, modifiers: .command)
        .disabled(!ModuleMenuPolicy.isDeleteEnabled(hasSelection: root.currentSelectedItemId != nil, isListFocused: isListFocused))
    }

    private var item: (any ItemDataAccessible)? {
        guard let selectedItemId = root.currentSelectedItemId else { return nil }
        return root.itemControllable.itemOrEmpty(for: selectedItemId)
    }
}

#Preview {
    DeleteItemButton(root: ItemRootController.fake)
}
#endif
