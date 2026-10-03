// @copyright André Trettin

import SwiftUI

struct ListRootContextMenu: View {
    init(root: any ItemRootControllable, controller: ContextMenuMultiController, parentItem: (any ItemDataAccessible)?, currentSelected: UUID? = nil, listController: (any FolderListControllable)? = nil) {
        self.root = root
        self.controller = controller
        self.parentItem = parentItem
        self.currentSelected = currentSelected
        self.listController = listController
    }

    let root: any ItemRootControllable
    let controller: ContextMenuMultiController
    let parentItem: (any ItemDataAccessible)?
    let currentSelected: UUID?
    let listController: (any FolderListControllable)?

    @Environment(\.navigator) private var navigator
    @Environment(ScenesManager.self) private var scenesManager
    @Environment(\.itemGenerationAction) private var itemGenerationAction
    
    var body: some View {
        let parent = self.parent
        EditItemView(root: root, title: title)
        DuplicateItemView(controller: controller, currentSelected: currentSelected, title: title)
        if !listDisplayModel.isListMode {
            Divider()
            AddItemView(controller: controller, currentSelected: currentSelected, listController: listController, title: title)
            MoveItemView(controller: controller, currentSelected: currentSelected, listController: listController, title: title)
        }
        removeActions(parent: parent)
        Divider()
        OpenFolderView(listController: listController, currentSelected: currentSelected, title: title)
        CloseParentFolderView(listController: listController, currentSelected: currentSelected)
        Divider()
        ExportItemView(controller: controller, currentSelected: currentSelected, title: title)
        GroupEditView(controller: controller, currentSelected: currentSelected, title: title)
        if canGenerate {
            GenerateItemView(currentSelected: currentSelected, title: title)
        }
        #if !os(tvOS)
        if root.viewControllable.supportsBatchExtraction {
            BatchExtractionView(controller: controller, currentSelected: currentSelected, title: title)
        }
        #endif
        Divider()
        SpaceActionView(root: root, currentSelected: currentSelected, title: title)
        Divider()
        DeleteItemView(root: root, controller: controller, currentSelected: currentSelected, parentItem: parentItem, title: title)
    }
}

private extension ListRootContextMenu {
    var title: String {
        controller.itemName(currentSelected: currentSelected)
    }
    
    var parent: (any ItemDataAccessible)? {
        parentItem ?? controller.parentItem(currentSelected: currentSelected)
    }

    @ViewBuilder func removeActions(parent: (any ItemDataAccessible)?) -> some View {
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

    var canGenerate: Bool {
        guard itemGenerationAction.isEnabled,
              let currentSelected,
              let item = root.itemControllable.itemSync(for: currentSelected)
        else {
            return false
        }
        return root.configurable.module == .table && !item.specialCategory
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
            listController?.update(debounce: false)
        } label: {
            Label {
                Text("Remove \(title) from \(removeEntryTitle(oneUp: oneUp))", bundle: .module)
            } icon: {
                Image(systemName: "rectangle.stack.badge.minus")
            }
        }
    }

}

private struct GenerateItemView: View {
    @Environment(\.itemGenerationAction) private var itemGenerationAction

    let currentSelected: UUID?
    let title: String

    var body: some View {
        Button {
            guard let currentSelected else { return }
            itemGenerationAction(currentSelected)
        } label: {
            Label {
                Text("Generate from \(title)", bundle: .module)
            } icon: {
                Image(systemName: "gear")
            }
        }
    }
}

private struct SpaceActionView: View {
    @Environment(ScenesManager.self) private var scenesManager

    let root: any ItemRootControllable
    let currentSelected: UUID?
    let title: String

    var body: some View {
        Button {
            ItemPrimaryAction.perform(
                root: root,
                scenesManager: scenesManager,
                itemId: currentSelected
            )
        } label: {
            let isCustom = root.viewControllable.hasCustomSpaceAction
            Label {
                Text(isCustom ? "Play/Roll \(title)" : "View \(title)", bundle: .module)
            } icon: {
                Image(systemName: isCustom ? "play.fill" : "eye")
            }
        }
        #if !os(tvOS)
        .keyboardShortcut(.return, modifiers: [])
        #endif
        .disabled(!ItemPrimaryAction.canPerform(root: root, itemId: currentSelected))
    }
}

private struct EditItemView: View {
    let root: any ItemRootControllable
    let title: String

    var body: some View {
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
}

private struct OpenFolderView: View {
    let listController: (any FolderListControllable)?
    let currentSelected: UUID?
    let title: String

    var body: some View {
        Button {
            withAnimation {
                _ = listController?.toggleFolder(itemId: currentSelected)
            }
        } label: {
            Label {
                Text(
                    (listController?.isFolderOpen(itemId: currentSelected) ?? false)
                        ? "Close \(title)"
                        : "Open \(title)",
                    bundle: .module
                )
            } icon: {
                Image(
                    systemName: (listController?.isFolderOpen(itemId: currentSelected) ?? false)
                        ? "chevron.up"
                        : "chevron.down"
                )
            }
        }
        #if !os(tvOS)
        .keyboardShortcut(.space, modifiers: [])
        #endif
        .disabled(!(listController?.canToggleFolder(itemId: currentSelected) ?? false))
    }
}

private struct CloseParentFolderView: View {
    let listController: (any FolderListControllable)?
    let currentSelected: UUID?

    var body: some View {
        Button {
            withAnimation { listController?.closeParentFolder(of: currentSelected ?? UUID()) }
        } label: {
            Label {
                Text("Close parent folder", bundle: .module)
            } icon: {
                Image(systemName: "chevron.up")
            }
        }
        .disabled(!(listController?.hasParentFolder(itemId: currentSelected) ?? false))
    }
}

private struct DuplicateItemView: View {
    let controller: ContextMenuMultiController
    let currentSelected: UUID?
    let title: String

    var body: some View {
        Button {
            controller.duplicateItem(currentSelected: currentSelected)
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
}

private struct DeleteItemView: View {
    @Environment(\.navigator) private var navigator

    let root: any ItemRootControllable
    let controller: ContextMenuMultiController
    let currentSelected: UUID?
    let parentItem: (any ItemDataAccessible)?
    let title: String

    var body: some View {
        Button(role: .destructive) {
            var removingItems: [ItemRowModel] = []
            withAnimation {
                removingItems = controller.deleteItem(currentSelected: currentSelected)
                guard !removingItems.isEmpty else { return }
                root.removeEntryListModel.removeItems = root.editControllable.markCollectionItemsForRemoval(for: removingItems)
            }
            // Nothing selected: opening the panel showed the previous deletion's list.
            // See CODE_AUDIT_Folder §5.12.
            guard !removingItems.isEmpty else { return }
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
        // Every collection kind (album, playlist, dice bag, …), not only `.collection`: in a
        // collection's list Delete would remove the item itself. See CODE_AUDIT_Folder §5.29.
        .disabled(parentItem?.category.isCollection ?? false)
    }
}

private struct ExportItemView: View {
    @Environment(\.navigator) private var navigator

    let controller: ContextMenuMultiController
    let currentSelected: UUID?
    let title: String

    var body: some View {
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
}

private struct GroupEditView: View {
    @Environment(\.navigator) private var navigator

    let controller: ContextMenuMultiController
    let currentSelected: UUID?
    let title: String

    var body: some View {
        Button {
            let route = controller.groupEditor(currentSelected: currentSelected)
            navigator.navigate(to: route, method: .sheet)
        } label: {
            Label {
                Text("Group editor for \(title)", bundle: .module)
            } icon: {
                Image(systemName: "long.text.page.and.pencil")
            }
        }
        #if !os(tvOS)
        .keyboardShortcut("g", modifiers: [.command, .control])
        #endif
    }
}

#if !os(tvOS)
private struct BatchExtractionView: View {
    @Environment(\.navigator) private var navigator

    let controller: ContextMenuMultiController
    let currentSelected: UUID?
    let title: String

    var body: some View {
        Button {
            let ids = controller.selection(currentSelected: currentSelected)
            navigator.navigate(to: InternalRoute.batchExtraction(ids: ids), method: .sheet)
        } label: {
            Label {
                Text("Extract information for \(title)", bundle: .module)
            } icon: {
                Image(systemName: "sparkles")
            }
        }
        .accessibilityHint(Text("Analyzes selected items with AI", bundle: .module))
    }
}
#endif

private struct MoveItemView: View {
    let controller: ContextMenuMultiController
    let currentSelected: UUID?
    let listController: (any FolderListControllable)?
    let title: String

    var body: some View {
        Menu {
            ForEach(controller.folderItems(currentSelected: currentSelected)) { folder in
                Button {
                    controller.moveItem(currentSelected: currentSelected, to: folder)
                    listController?.update(debounce: false)
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
}

private struct AddItemView: View {
    let controller: ContextMenuMultiController
    let currentSelected: UUID?
    let listController: (any FolderListControllable)?
    let title: String

    var body: some View {
        Menu {
            ForEach(controller.collectionItems(currentSelected: currentSelected)) { folder in
                Button {
                    controller.addItem(currentSelected: currentSelected, to: folder)
                    listController?.update(debounce: false)
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
}

#Preview {
    let fixture = FakeItemRootControllerFixture()
    ListRootContextMenu(
        root: fixture.root,
        controller: ContextMenuMultiController(
            editController: fixture.editController,
            itemController: fixture.itemController,
            listModel: fixture.folderListController.listModel
        ),
        parentItem: nil,
        listController: fixture.folderListController
    )
    .padding()
}
