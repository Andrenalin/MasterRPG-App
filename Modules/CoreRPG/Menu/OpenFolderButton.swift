// @copyright André Trettin

import SwiftUI

#if !os(tvOS)
struct OpenFolderButton: View {
    let root: any ItemRootControllable
    var isListFocused = true

    var body: some View {
        Button {
            withAnimation {
                _ = root.folderListControllable.toggleSelectedFolder()
            }
        } label: {
            Label {
                Text(
                    root.folderListControllable.isFolderOpen(
                        itemId: root.currentSelectedItemId
                    ) ? "Close Folder" : "Open Folder",
                    bundle: .module
                )
            } icon: {
                Image(
                    systemName: root.folderListControllable.isFolderOpen(
                        itemId: root.currentSelectedItemId
                    ) ? "chevron.up" : "chevron.down"
                )
            }
        }
        .keyboardShortcut(.space, modifiers: [])
        .disabled(
            !isListFocused
                || !root.folderListControllable.canToggleFolder(
                    itemId: root.currentSelectedItemId
                )
        )
    }
}

#Preview {
    OpenFolderButton(root: ItemRootController.fake)
}
#endif
