// @copyright André Trettin

import SwiftUI

#if !os(tvOS)
struct DuplicateItemButton: View {
    let root: any ItemRootControllable

    var body: some View {
        Button {
            if let item {
                Task {
                    await root.editControllable.duplicate(item: item)
                }
            }
        } label: {
            Label {
                Text("Duplicate \(item?.name ?? "")", bundle: .module)
            } icon: {
                Image(systemName: "doc.on.doc")
            }
        }
        .keyboardShortcut("D", modifiers: [.command, .shift])
        .disabled(root.currentSelectedItemId == nil)
    }

    private var item: (any ItemDataAccessable)? {
        guard let selectedItemId = root.currentSelectedItemId else { return nil }
        return root.itemControllable.itemOrEmpty(for: selectedItemId)
    }
}

#Preview {
    DuplicateItemButton(root: ItemRootController.fake)
}
#endif
