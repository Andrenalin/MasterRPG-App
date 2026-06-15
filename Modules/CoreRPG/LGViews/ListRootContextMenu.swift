// @copyright André Trettin

import SwiftUI

struct ListRootContextMenu: View {
    init(root: any ItemRootControllable, controller: ContextMenuMultiController, parentItem: (any ItemDataAccessable)?, currentSelected: UUID? = nil, listController: (any FolderListControllable)? = nil) {
        self.root = root
        self.controller = controller
        self.parentItem = parentItem
        self.currentSelected = currentSelected
        self.listController = listController
    }

    let root: any ItemRootControllable
    let controller: ContextMenuMultiController
    let parentItem: (any ItemDataAccessable)?
    let currentSelected: UUID?
    let listController: (any FolderListControllable)?

    @Environment(\.navigator) private var navigator
    
    var body: some View {
        let parent = self.parent
        editItemView
        duplicateItemView
        if !listDisplayModel.isListMode {
            Divider()
            addItemView
            moveItemView
        }
        removeActions(parent: parent)
        Divider()
        openFolderView
        closeParentFolderView
        Divider()
        exportItemView
        groupEditView
        #if !os(tvOS)
        if root.viewControllable.supportsBatchExtraction {
            batchExtractionView
        }
        #endif
        Divider()
        spaceActionView
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

    @ViewBuilder func removeActions(parent: (any ItemDataAccessable)?) -> some View {
        if controller.hasDifferentFolders(for: parent) {
            removeItemView(oneUp: true)
        }
        if parent?.specialCategory ?? false {
            removeItemView(oneUp: false)
        }
    }

    var listDisplayModel: ListDisplayModel {
        listController?.listDisplayModel ?? ListDisplayModel()
    }
    
    var spaceActionView: some View {
        Button {
            root.navigationModel.triggerSpaceAction = true
        } label: {
            let isCustom = root.viewControllable.hasCustomSpaceAction
            Label {
                Text(isCustom ? "Play/Roll \(title)" : "View \(title)", bundle: .module)
            } icon: {
                Image(systemName: isCustom ? "play.fill" : "eye")
            }
        }
        #if !os(tvOS)
        .keyboardShortcut(.return, modifiers: [.command, .shift])
        #endif
    }

    var editItemView: some View {
        Button {
            root.navigationModel.openHeaderEditor = true
        } label: {
            Label {
                Text("Edit \(title)", bundle: .module)
            } icon: {
                Image(systemName: "pencil")
            }
        }
        #if !os(tvOS)
        .keyboardShortcut("e", modifiers: [.command, .shift])
        #endif
    }

    var openFolderView: some View {
        Button {
            withAnimation { listController?.openFolder(itemId: currentSelected ?? UUID()) }
        } label: {
            Label {
                Text("Open \(title)", bundle: .module)
            } icon: {
                Image(systemName: "chevron.down")
            }
        }
        #if !os(tvOS)
        .keyboardShortcut(.rightArrow, modifiers: [.command, .shift])
        #endif
        .disabled(!(listController?.canOpenFolder(itemId: currentSelected) ?? false))
    }

    var closeParentFolderView: some View {
        Button {
            withAnimation { listController?.closeParentFolder(of: currentSelected ?? UUID()) }
        } label: {
            Label {
                Text("Close Parent Folder", bundle: .module)
            } icon: {
                Image(systemName: "chevron.up")
            }
        }
        #if !os(tvOS)
        .keyboardShortcut(.leftArrow, modifiers: [.command, .shift])
        #endif
        .disabled(!(listController?.hasParentFolder(itemId: currentSelected) ?? false))
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
        .keyboardShortcut("D", modifiers: [.command, .shift])
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
        .keyboardShortcut("e", modifiers: [.command, .control])
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
        .keyboardShortcut("g", modifiers: [.command, .control])
        #endif
    }

    #if !os(tvOS)
    var batchExtractionView: some View {
        Button {
            let ids = controller.selection(currentSelected: currentSelected)
            navigator.navigate(to: InternalRoute.batchExtraction(ids: ids), method: .sheet)
        } label: {
            Label {
                Text("Extract Information for \(title)", bundle: .module)
            } icon: {
                Image(systemName: "sparkles")
            }
        }
        .accessibilityHint(Text("Analyzes selected items with AI", bundle: .module))
    }
    #endif
    
    var moveItemView: some View {
        Menu {
            ForEach(controller.folderItems(currentSelected: currentSelected)) { folder in
                Button {
                    controller.moveItem(currentSelected: currentSelected, to: folder)
                    Task {
                        listController?.update()
                    }
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
                    Task {
                        listController?.update()
                    }
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
            controller.removeItemsFromFolder(currentSelected: currentSelected, parentId: parent?.id, oneUp: oneUp)
            Task {
                listController?.update()
            }
        } label: {
            Label {
                Text("Remove \(title) from \(removeEntryTitle(oneUp: oneUp))", bundle: .module)
            } icon: {
                Image(systemName: "rectangle.stack.badge.minus")
            }
        }
    }

}
