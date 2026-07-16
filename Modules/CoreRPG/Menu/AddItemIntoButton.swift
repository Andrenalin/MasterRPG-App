// @copyright André Trettin

import SwiftUI

#if !os(tvOS)
struct AddItemIntoButton: View {
    let root: any ItemRootControllable

    var body: some View {
        let collections = self.collections
        Menu {
            ForEach(collections) { folder in
                Button {
                    menuController.addItem(currentSelected: root.currentSelectedItemId, to: folder)
                    root.folderListControllable.resetFilter()
                } label: {
                    Label { Text(folder.name) } icon: { Image(systemName: root.itemControllable.collectionCategory.icon) }
                }
            }
        } label: {
            Label {
                Text("Add \(item?.name ?? "") into", bundle: .module)
            } icon: {
                Image(systemName: root.itemControllable.collectionCategory.icon)
            }
        }
        .disabled(collections.isEmpty)
    }

    private var menuController: ContextMenuMultiController {
        ContextMenuMultiController(editController: root.editControllable, itemController: root.itemControllable, listModel: root.folderListControllable.listModel)
    }

    private var collections: [FolderRepresentable] {
        menuController.collectionItems(currentSelected: root.currentSelectedItemId)
    }

    private var item: (any ItemDataAccessable)? {
        guard let selectedItemId = root.currentSelectedItemId else { return nil }
        return root.itemControllable.itemOrEmpty(for: selectedItemId)
    }
}

#Preview {
    AddItemIntoButton(root: ItemRootController.fake)
}
#endif
