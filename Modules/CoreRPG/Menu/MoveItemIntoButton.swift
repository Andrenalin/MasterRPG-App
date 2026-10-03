// @copyright André Trettin

import SwiftUI

#if !os(tvOS)
struct MoveItemIntoButton: View {
    let root: any ItemRootControllable

    var body: some View {
        Menu {
            // The folder list is built only for the menu's content; the command itself only asks
            // whether there is one. See CODE_AUDIT_Folder §7.4.
            MoveItemIntoMenuContent(root: root)
        } label: {
            Label {
                Text("Move \(item?.name ?? "") into", bundle: .module)
            } icon: {
                Image(systemName: "folder")
            }
        }
        .disabled(!root.menuController.hasFolderItems(currentSelected: root.currentSelectedItemId))
    }

    private var item: (any ItemDataAccessible)? {
        guard let selectedItemId = root.currentSelectedItemId else { return nil }
        return root.itemControllable.itemOrEmpty(for: selectedItemId)
    }
}

private struct MoveItemIntoMenuContent: View {
    let root: any ItemRootControllable

    var body: some View {
        let menuController = root.menuController
        ForEach(menuController.folderItems(currentSelected: root.currentSelectedItemId)) { folder in
            Button {
                menuController.moveItem(currentSelected: root.currentSelectedItemId, to: folder)
                // Same refresh as the context menu. See CODE_AUDIT_Folder §5.29.
                root.folderListControllable.update(debounce: false)
            } label: {
                Label { Text(folder.name) } icon: { Image(systemName: "folder") }
            }
        }
    }
}

#Preview {
    MoveItemIntoButton(root: ItemRootController.fake)
}
#endif
