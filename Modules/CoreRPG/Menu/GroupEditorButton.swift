// @copyright André Trettin

import SwiftUI

#if !os(tvOS)
struct GroupEditorButton: View {
    let root: any ItemRootControllable

    var body: some View {
        Button {
            root.navigationModel.triggerGroupEditor = true
        } label: {
            Label {
                Text("Group Editor for \(item?.name ?? "")", bundle: .module)
            } icon: {
                Image(systemName: "long.text.page.and.pencil")
            }
        }
        .keyboardShortcut("g", modifiers: [.command, .control])
        .disabled(root.currentSelectedItemId == nil)
    }

    private var item: (any ItemDataAccessable)? {
        guard let selectedItemId = root.currentSelectedItemId else { return nil }
        return root.itemControllable.itemOrEmpty(for: selectedItemId)
    }
}

#Preview {
    GroupEditorButton(root: ItemRootController.fake)
}
#endif
