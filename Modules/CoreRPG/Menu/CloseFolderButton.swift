// @copyright André Trettin

import SwiftUI

#if !os(tvOS)
struct CloseFolderButton: View {
    let root: any ItemRootControllable

    var body: some View {
        Button {
            withAnimation { root.folderListControllable.closeParentFolder() }
        } label: {
            Label {
                Text("Close Parent Folder", bundle: .module)
            } icon: {
                Image(systemName: "chevron.up")
            }
        }
        .keyboardShortcut(.leftArrow, modifiers: [.command, .shift])
        .disabled(!root.folderListControllable.hasParentFolder(itemId: root.currentSelectedItemId))
    }
}

#Preview {
    CloseFolderButton(root: ItemRootController.fake)
}
#endif
