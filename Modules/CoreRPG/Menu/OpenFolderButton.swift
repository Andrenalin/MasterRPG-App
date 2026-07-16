// @copyright André Trettin

import SwiftUI

#if !os(tvOS)
struct OpenFolderButton: View {
    let root: any ItemRootControllable

    var body: some View {
        Button {
            withAnimation { root.folderListControllable.openSelectedFolder() }
        } label: {
            Label {
                Text("Open Folder", bundle: .module)
            } icon: {
                Image(systemName: "chevron.down")
            }
        }
        .keyboardShortcut(.rightArrow, modifiers: [.command, .shift])
        .disabled(!root.folderListControllable.canOpenFolder(itemId: root.currentSelectedItemId))
    }
}

#Preview {
    OpenFolderButton(root: ItemRootController.fake)
}
#endif
