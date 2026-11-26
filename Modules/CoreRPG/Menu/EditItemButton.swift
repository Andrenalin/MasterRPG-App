// @copyright André Trettin

import SwiftUI

#if !os(tvOS)
struct EditItemButton: View {
    let root: any ItemRootControllable

    var body: some View {
        Button {
            root.navigationModel.openHeaderEditor = true
        } label: {
            Label {
                Text.itemMenuTitle(name: item?.name, plain: "Edit", named: "Edit \(item?.name ?? "")")
            } icon: {
                Image(systemName: "pencil")
            }
        }
        .keyboardShortcut("e", modifiers: [.command, .shift])
        .disabled(root.currentSelectedItemId == nil)
    }

    private var item: (any ItemDataAccessible)? {
        guard let selectedItemId = root.currentSelectedItemId else { return nil }
        return root.itemControllable.itemOrEmpty(for: selectedItemId)
    }
}

#Preview {
    EditItemButton(root: ItemRootController.fake)
}
#endif
