// @copyright André Trettin

import SwiftUI

/// "Move <item> into" a folder or "Add <item> into" a collection, the same view in the menu bar
/// and in the list's context menu. The two places had four drifted copies.
/// See CODE_AUDIT_Folder §9.7.
struct FolderPlacementMenu: View {
    let isFolder: Bool
    let controller: ContextMenuMultiController
    let currentSelected: UUID?
    let listController: (any FolderListControllable)?

    var body: some View {
        let title = controller.itemName(currentSelected: currentSelected)
        Menu {
            // The target list is built only for the menu's content; the command itself only asks
            // whether there is one. See CODE_AUDIT_Folder §7.4.
            FolderPlacementMenuContent(
                isFolder: isFolder,
                controller: controller,
                currentSelected: currentSelected,
                listController: listController
            )
        } label: {
            Label {
                if isFolder {
                    Text("Move \(title) into", bundle: .module)
                } else {
                    Text("Add \(title) into", bundle: .module)
                }
            } icon: {
                Image(systemName: isFolder ? "folder" : controller.collectionIcon)
            }
        }
        .disabled(!controller.hasPlacementTargets(currentSelected: currentSelected, isFolder: isFolder))
    }
}

private struct FolderPlacementMenuContent: View {
    let isFolder: Bool
    let controller: ContextMenuMultiController
    let currentSelected: UUID?
    let listController: (any FolderListControllable)?

    var body: some View {
        ForEach(controller.placementTargets(currentSelected: currentSelected, isFolder: isFolder)) { target in
            Button {
                controller.place(currentSelected: currentSelected, in: target)
                // Refresh at once, not after the debounce. See CODE_AUDIT_Folder §5.29.
                listController?.update(debounce: false)
            } label: {
                Label { Text(target.name) } icon: { Image(systemName: isFolder ? "folder" : controller.collectionIcon) }
            }
        }
    }
}

/// The menu-bar entry for moving the selected item into a folder.
struct MoveItemIntoButton: View {
    let root: any ItemRootControllable

    var body: some View {
        FolderPlacementMenu(
            isFolder: true,
            controller: root.menuController,
            currentSelected: root.currentSelectedItemId,
            listController: root.folderListControllable
        )
    }
}

/// The menu-bar entry for adding the selected item to a collection.
struct AddItemIntoButton: View {
    let root: any ItemRootControllable

    var body: some View {
        FolderPlacementMenu(
            isFolder: false,
            controller: root.menuController,
            currentSelected: root.currentSelectedItemId,
            listController: root.folderListControllable
        )
    }
}

/// Opens or closes the folder `itemId`, from the menu bar and the context menu alike.
/// See CODE_AUDIT_Folder §9.7.
struct OpenFolderButton: View {
    init(listController: (any FolderListControllable)?, itemId: UUID?, title: String, isEnabled: Bool = true) {
        self.listController = listController
        self.itemId = itemId
        self.title = title
        self.isEnabled = isEnabled
    }

    /// The menu-bar command acts on the selected row. By item id it took the first row showing
    /// the item, and a collection member has two rows. See CODE_AUDIT_21 §5.31.
    init(root: any ItemRootControllable, isListFocused: Bool = true) {
        self.init(
            listController: root.folderListControllable,
            itemId: root.folderListControllable.listModel.selected ?? root.currentSelectedItemId,
            title: root.menuController.itemName(currentSelected: root.currentSelectedItemId),
            isEnabled: isListFocused
        )
    }

    let listController: (any FolderListControllable)?
    let itemId: UUID?
    let title: String
    let isEnabled: Bool

    var body: some View {
        let isOpen = listController?.isFolderOpen(itemId: itemId) ?? false
        Button {
            withAnimation {
                _ = listController?.toggleFolder(itemId: itemId)
            }
        } label: {
            Label {
                if isOpen {
                    Text("Close \(title)", bundle: .module)
                } else {
                    Text("Open \(title)", bundle: .module)
                }
            } icon: {
                Image(systemName: isOpen ? "chevron.up" : "chevron.down")
            }
        }
#if !os(tvOS)
        // Not in selection mode: the list handles Space itself there, on the keyboard row. The
        // menu command acts on the single selected row and would take the key first.
        .keyboardShortcut(listController?.listDisplayModel.isSelectionMode == true ? nil : KeyboardShortcut(.space, modifiers: []))
#endif
        .disabled(!isEnabled || !(listController?.canToggleFolder(itemId: itemId) ?? false))
    }
}

/// Closes the open folder that contains `itemId`, from the menu bar and the context menu alike.
/// See CODE_AUDIT_Folder §9.7.
struct CloseFolderButton: View {
    init(listController: (any FolderListControllable)?, itemId: UUID?) {
        self.listController = listController
        self.itemId = itemId
    }

    /// The selected row, like `OpenFolderButton.init(root:)`. See CODE_AUDIT_21 §5.31.
    init(root: any ItemRootControllable) {
        self.init(
            listController: root.folderListControllable,
            itemId: root.folderListControllable.listModel.selected ?? root.currentSelectedItemId
        )
    }

    let listController: (any FolderListControllable)?
    let itemId: UUID?

    var body: some View {
        Button {
            guard let itemId else { return }
            withAnimation { listController?.closeParentFolder(of: itemId) }
        } label: {
            Label {
                Text("Close Parent Folder", bundle: .module)
            } icon: {
                Image(systemName: "chevron.up")
            }
        }
        .disabled(!(listController?.hasParentFolder(itemId: itemId) ?? false))
    }
}

#Preview {
    MoveItemIntoButton(root: ItemRootController.fake)
}

#Preview {
    AddItemIntoButton(root: ItemRootController.fake)
}

#Preview {
    OpenFolderButton(root: ItemRootController.fake)
}

#Preview {
    CloseFolderButton(root: ItemRootController.fake)
}
