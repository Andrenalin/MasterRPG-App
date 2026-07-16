// @copyright André Trettin

import SwiftUI

#if !os(tvOS)
struct MoveItemIntoButton: View {
    let root: any ItemRootControllable

    var body: some View {
        let folders = self.folders
        Menu {
            ForEach(folders) { folder in
                Button {
                    menuController.moveItem(currentSelected: root.currentSelectedItemId, to: folder)
                    root.folderListControllable.resetFilter()
                } label: {
                    Label { Text(folder.name) } icon: { Image(systemName: "folder") }
                }
            }
        } label: {
            Label {
                Text("Move \(item?.name ?? "") into", bundle: .module)
            } icon: {
                Image(systemName: "folder")
            }
        }
        .disabled(folders.isEmpty)
    }

    private var menuController: ContextMenuMultiController {
        ContextMenuMultiController(editController: root.editControllable, itemController: root.itemControllable, listModel: root.folderListControllable.listModel)
    }

    private var folders: [FolderRepresentable] {
        menuController.folderItems(currentSelected: root.currentSelectedItemId)
    }

    private var item: (any ItemDataAccessable)? {
        guard let selectedItemId = root.currentSelectedItemId else { return nil }
        return root.itemControllable.itemOrEmpty(for: selectedItemId)
    }
}

#Preview {
    MoveItemIntoButton(root: ItemRootController.fake)
}
#endif
