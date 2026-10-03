// @copyright André Trettin

import SwiftUI

#if !os(tvOS)
struct AddItemIntoButton: View {
    let root: any ItemRootControllable

    var body: some View {
        Menu {
            // The collection list is built only for the menu's content; the command itself only
            // asks whether there is one. See CODE_AUDIT_Folder §7.4.
            AddItemIntoMenuContent(root: root)
        } label: {
            Label {
                Text("Add \(item?.name ?? "") into", bundle: .module)
            } icon: {
                Image(systemName: root.itemControllable.collectionCategory.icon)
            }
        }
        .disabled(!root.menuController.hasCollectionItems(currentSelected: root.currentSelectedItemId))
    }

    private var item: (any ItemDataAccessible)? {
        guard let selectedItemId = root.currentSelectedItemId else { return nil }
        return root.itemControllable.itemOrEmpty(for: selectedItemId)
    }
}

private struct AddItemIntoMenuContent: View {
    let root: any ItemRootControllable

    var body: some View {
        let menuController = root.menuController
        ForEach(menuController.collectionItems(currentSelected: root.currentSelectedItemId)) { collection in
            Button {
                menuController.addItem(currentSelected: root.currentSelectedItemId, to: collection)
                // Same refresh as the context menu. See CODE_AUDIT_Folder §5.29.
                root.folderListControllable.update(debounce: false)
            } label: {
                Label { Text(collection.name) } icon: { Image(systemName: root.itemControllable.collectionCategory.icon) }
            }
        }
    }
}

#Preview {
    AddItemIntoButton(root: ItemRootController.fake)
}
#endif
