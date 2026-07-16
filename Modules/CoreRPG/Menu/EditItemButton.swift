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
                Text("Edit \(item?.name ?? "")", bundle: .module)
            } icon: {
                Image(systemName: "pencil")
            }
        }
        .keyboardShortcut("e", modifiers: [.command, .shift])
        .disabled(root.currentSelectedItemId == nil)
    }

    private var item: (any ItemDataAccessable)? {
        guard let selectedItemId = root.currentSelectedItemId else { return nil }
        return root.itemControllable.itemOrEmpty(for: selectedItemId)
    }
}

#Preview {
    EditItemButton(root: ItemRootController.fake)
}
#endif
