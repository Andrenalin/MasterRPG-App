// @copyright André Trettin

import SwiftUI

#if !os(tvOS)
struct ExportItemButton: View {
    let root: any ItemRootControllable

    var body: some View {
        Button {
            root.navigationModel.triggerExport = true
        } label: {
            Label {
                Text("Export \(item?.name ?? "")", bundle: .module)
            } icon: {
                Image(systemName: "square.and.arrow.up")
            }
        }
        .keyboardShortcut("e", modifiers: [.command, .control])
        .disabled(root.currentSelectedItemId == nil)
    }

    private var item: (any ItemDataAccessible)? {
        guard let selectedItemId = root.currentSelectedItemId else { return nil }
        return root.itemControllable.itemOrEmpty(for: selectedItemId)
    }
}

#Preview {
    ExportItemButton(root: ItemRootController.fake)
}
#endif
