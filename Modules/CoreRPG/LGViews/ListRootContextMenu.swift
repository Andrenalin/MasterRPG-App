// @copyright André Trettin

import SwiftUI

public struct ListRootContextMenu: View {
    public init(controller: any ItemListContextMenuControllable, parentItem: (any ItemDataAccessable)?, currentSelected: UUID? = nil, listController: (any FolderListControllable)? = nil) {
        self.controller = controller
        self.parentItem = parentItem
        self.currentSelected = currentSelected
        self.listController = listController
    }

    let controller: ItemListContextMenuControllable
    let parentItem: (any ItemDataAccessable)?
    let currentSelected: UUID?
    let listController: (any FolderListControllable)?

    @Environment(ItemRootController.self) private var root
    @Environment(\.navigator) private var navigator
    @Environment(ListDisplayModel.self) private var listDisplayModel
    
    public var body: some View {
        duplicateItemView
        if !listDisplayModel.isListMode {
            Divider()
            addItemView
            moveItemView
        }
        if parentItem?.specialCategory ?? false {
            removeItemView
        }
        Divider()
        exportItemView
        groupEditView
        Divider()
        deleteItemView
    }
}

private extension ListRootContextMenu {
    var title: String {
        controller.itemName(currentSelected: currentSelected)
    }

    var duplicateItemView: some View {
        Button {
            Task {
                await controller.duplicateItem(currentSelected: currentSelected)
            }
        } label: {
            Label {
                Text("Duplicate \(title)", bundle: .module)
            } icon: {
                Image(systemName: "doc.on.doc")
            }
        }
    }

    var deleteItemView: some View {
        Button(role: .destructive) {
            withAnimation {
                let removingItems = controller.deleteItem(currentSelected: currentSelected)
                guard !removingItems.isEmpty else { return }
                root.removeEntryListModel.removeItems = root.editControllable.markCollectionItemsForRemoval(for: removingItems)
            }
            navigator.navigate(to: InternalRoute.removeAlert, method: .managedSheet)
        } label: {
            Label {
                Text("Delete \(title)", bundle: .module)
            } icon: {
                Image(systemName: "trash")
            }
        }
        .disabled((parentItem?.category ?? .entry) == .collection)
    }

    var exportItemView: some View {
        Button {
            let route = controller.exportItem(currentSelected: currentSelected)
            navigator.navigate(to: route, method: .sheet)
        } label: {
            Label {
                Text("Export \(title)", bundle: .module)
            } icon: {
                Image(systemName: "square.and.arrow.up")
            }
        }
    }

    var generateLinkView: some View {
        Button {
            withAnimation { controller.generateLink(currentSelected: currentSelected) }
        } label: {
            Label {
                Text("Link for \(title)", bundle: .module)
            } icon: {
                Image(systemName: "link")
            }
        }
    }

    var groupEditView: some View {
        Button {
            let route = controller.groupEditor(currentSelected: currentSelected)
            navigator.navigate(to: route, method: .sheet)
        } label: {
            Label {
                Text("Group Editor for \(title)", bundle: .module)
            } icon: {
                Image(systemName: "long.text.page.and.pencil")
            }
        }
    }
    
    var moveItemView: some View {
        Menu {
            ForEach(controller.folderItems(currentSelected: currentSelected)) { folder in
                Button {
                    controller.moveItem(currentSelected: currentSelected, to: folder)
                } label: {
                    Label {
                        Text(folder.name)
                    } icon: {
                        Image(systemName: "folder")
                    }
                }
            }
        } label: {
            Label {
                Text("Move \(title) into", bundle: .module)
            } icon: {
                Image(systemName: "folder")
            }
        }
    }

    var addItemView: some View {
        Menu {
            ForEach(controller.collectionItems(currentSelected: currentSelected)) { folder in
                Button {
                    controller.addItem(currentSelected: currentSelected, to: folder)
                } label: {
                    Label {
                        Text(folder.name)
                    } icon: {
                        Image(systemName: controller.collectionIcon)
                    }
                }
            }
        } label: {
            Label {
                Text("Add \(title) into", bundle: .module)
            } icon: {
                Image(systemName: controller.collectionIcon)
            }
        }
    }
    
    var removeEntryTitle: String {
        (parentItem?.category ?? .entry).title
    }
    
    var removeItemView: some View {
        Button {
            guard let itemId = currentSelected, let parentId = parentItem?.id else { return }
            withAnimation {
                root.editControllable.remove(itemId: itemId, parentId: parentId)
                // Refresh the detail list from the updated parent model entries
                listController?.update()
                // Also refresh the parent folder list
                root.folderListControllable.resetFilter()
            }
        } label: {
            Label {
                Text("Remove \(title) from \(removeEntryTitle)", bundle: .module)
            } icon: {
                Image(systemName: "rectangle.stack.badge.minus")
            }
        }
    }

}
