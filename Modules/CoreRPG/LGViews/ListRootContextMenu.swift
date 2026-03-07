// @copyright André Trettin

import SwiftUI

struct ListRootContextMenu: View {
    init(controller: ContextMenuMultiController, parentItem: (any ItemDataAccessable)?, currentSelected: UUID? = nil, listController: (any FolderListControllable)? = nil) {
        self.controller = controller
        self.parentItem = parentItem
        self.currentSelected = currentSelected
        self.listController = listController
    }

    let controller: ContextMenuMultiController
    let parentItem: (any ItemDataAccessable)?
    let currentSelected: UUID?
    let listController: (any FolderListControllable)?

    @Environment(ItemRootController.self) private var root
    @Environment(\.navigator) private var navigator
    @Environment(ListDisplayModel.self) private var listDisplayModel
    
    var body: some View {
        duplicateItemView
        if !listDisplayModel.isListMode {
            Divider()
            addItemView
            moveItemView
        }
        if controller.hasDifferentFolders(for: parent) {
            removeItemView(oneUp: true)
        }
        if parent?.specialCategory ?? false {
            removeItemView(oneUp: false)
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
    
    var parent: (any ItemDataAccessable)? {
        parentItem ?? controller.parentItem(currentSelected: currentSelected)
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
        #if !os(tvOS)
        .keyboardShortcut("d", modifiers: .command)
        #endif
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
        #if !os(tvOS)
        .keyboardShortcut(.delete, modifiers: .command)
        #endif
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
        #if !os(tvOS)
        .keyboardShortcut("e", modifiers: [.command, .shift])
        #endif
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
        #if !os(tvOS)
        .keyboardShortcut("l", modifiers: [.command, .shift])
        #endif
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
        #if !os(tvOS)
        .keyboardShortcut("g", modifiers: [.command, .option])
        #endif
    }
    
    var moveItemView: some View {
        Menu {
            ForEach(controller.folderItems(currentSelected: currentSelected)) { folder in
                Button {
                    controller.moveItem(currentSelected: currentSelected, to: folder)
                    listController?.update()
                    // Also refresh the parent folder list
                    root.folderListControllable.resetFilter()
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
        #if !os(tvOS)
        .keyboardShortcut("m", modifiers: [.command, .shift])
        #endif
    }

    var addItemView: some View {
        Menu {
            ForEach(controller.collectionItems(currentSelected: currentSelected)) { folder in
                Button {
                    controller.addItem(currentSelected: currentSelected, to: folder)
                    listController?.update()
                    // Also refresh the parent folder list
                    root.folderListControllable.resetFilter()
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
        #if !os(tvOS)
        .keyboardShortcut("a", modifiers: [.command, .shift])
        #endif
    }
    
    func removeEntryTitle(oneUp: Bool) -> String {
        guard let parent else { return String(localized: "Unknown", bundle: .module).localizedString }
        if parent.isFolder {
            var toName = String(localized: "Root", bundle: .module).localizedString
            if oneUp, let parentId = parent.parentId, let parentParent = root.itemControllable.itemSync(for: parentId) {
                toName = parentParent.name
            }
            return String(localized: "\(parent.name) to \(toName)", bundle: .module).localizedString
        } else {
            return parent.category.title
        }
    }
    
    func removeItemView(oneUp: Bool) -> some View {
        Button {
            guard let itemId = currentSelected, let parentId = parent?.id else { return }
            withAnimation {
                root.editControllable.remove(itemId: itemId, parentId: parentId, oneUp: oneUp)
                // Refresh the detail list from the updated parent model entries
                listController?.update()
                // Also refresh the parent folder list
                root.folderListControllable.resetFilter()
            }
        } label: {
            Label {
                Text("Remove \(title) from \(removeEntryTitle(oneUp: oneUp))", bundle: .module)
            } icon: {
                Image(systemName: "rectangle.stack.badge.minus")
            }
        }
        #if !os(tvOS)
        .keyboardShortcut("r", modifiers: [.command, .shift])
        #endif
    }

}
