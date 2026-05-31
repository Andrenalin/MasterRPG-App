// @copyright André Trettin

import SwiftUI

#if !os(tvOS)
public struct ModuleCommands: Commands {
    public init(root: any ItemRootControllable, scenesManager: ScenesManager, routeActions: RouteActions, key: AKKeyEquivalent) {
        self.root = root
        self.scenesManager = scenesManager
        self.routeActions = routeActions
        self.key = key
    }

    let root: any ItemRootControllable
    let scenesManager: ScenesManager
    let routeActions: RouteActions
    let key: AKKeyEquivalent

    @FocusedBinding(\.selectedModule) private var selectedModule: NetworkModules?
    @FocusedValue(\.listDisplayModel) private var listDisplayModel: ListDisplayModel?

    public var body: some Commands {
        CommandGroup(after: .windowArrangement) {
            LinkWindowCommandView(networkModule: root.configurable.module, scenesManager: scenesManager, key: key)
        }
        CommandGroup(after: .toolbar) {
            NavigateButton(root: root, routeActions: routeActions, key: key)
        }
        CommandGroup(after: .newItem) {
            AddItemButton(root: root, routeActions: routeActions, key: key)
            AddFolderButton(root: root, routeActions: routeActions, key: key)
            AddCollectionButton(root: root, routeActions: routeActions, key: key)
        }
        CommandGroup(before: .textEditing) {
            if selectedModule == root.configurable.module {
                SpaceActionButton(root: root, scenesManager: scenesManager)
                EditItemButton(root: root)
                DuplicateItemButton(root: root)
                ExportItemButton(root: root)
                GroupEditorButton(root: root)
                if root.viewControllable.supportsBatchExtraction {
                    BatchExtractionButton(root: root)
                }
                Divider()
                AddItemIntoButton(root: root)
                MoveItemIntoButton(root: root)
                Divider()
                DeleteItemButton(root: root)
                Divider()
            }
        }
        CommandGroup(replacing: .undoRedo) {
            if selectedModule == root.configurable.module {
                UndoButton(root: root)
                RedoButton(root: root)
            }
        }
        CommandGroup(before: .sidebar) {
            if selectedModule == root.configurable.module, let listDisplayModel {
                MenuDisplayModeToggle(listDisplayModel: listDisplayModel, showSelectionButton: true)
                Divider()
                OpenFolderButton(root: root)
                CloseFolderButton(root: root)
                Divider()
            }
        }
    }
}

struct NavigateButton: View {
    let root: any ItemRootControllable
    let routeActions: RouteActions
    let key: AKKeyEquivalent

    var body: some View {
        Button {
            routeActions.routePage(root.configurable.module, nil, nil)
        } label: {
            Label { Text("Show \(root.configurable.module.title)", bundle: .module) } icon: { Image(systemName: "eye") }
        }
        .keyboardShortcut(key, modifiers: [.command])
    }
}

struct AddItemButton: View {
    let root: any ItemRootControllable
    let routeActions: RouteActions
    let key: AKKeyEquivalent

    var body: some View {
        Button {
            Task {
                guard let item = await root.editControllable.addNew(type: .item) else { return }
                routeActions.routePage(root.configurable.module, item.id, nil)
            }
        } label: {
            Label { Text("New \(root.configurable.module.title)", bundle: .module) } icon: { Image(systemName: "plus") }
        }
        .keyboardShortcut(key, modifiers: [.command, .control])
    }
}

struct AddFolderButton: View {
    let root: any ItemRootControllable
    let routeActions: RouteActions
    let key: AKKeyEquivalent

    var body: some View {
        Button {
            Task {
                guard let item = await root.editControllable.addNew(type: .folder) else { return }
                routeActions.routePage(root.configurable.module, item.id, nil)
            }
        } label: {
            Label {
                Text(EditControllerAddType.folder.title)
            } icon: {
                Image(systemName: EditControllerAddType.folder.icon(collection: root.itemControllable.collectionCategory.icon))
            }
        }
        .keyboardShortcut(key, modifiers: [.command, .control, .shift])
        .disabled(root.folderListControllable.listDisplayModel.isListMode)
    }
}

struct AddCollectionButton: View {
    let root: any ItemRootControllable
    let routeActions: RouteActions
    let key: AKKeyEquivalent

    var body: some View {
        Button {
            Task {
                guard let item = await root.editControllable.addNew(type: .collection) else { return }
                routeActions.routePage(root.configurable.module, item.id, nil)
            }
        } label: {
            Label {
                Text(EditControllerAddType.collection.title)
            } icon: {
                Image(systemName: EditControllerAddType.collection.icon(collection: root.itemControllable.collectionCategory.icon))
            }
        }
        .keyboardShortcut(key, modifiers: [.command, .control, .option])
        .disabled(root.folderListControllable.listDisplayModel.isListMode)
    }
}

struct EditItemButton: View {
    let root: any ItemRootControllable

    var body: some View {
        Button {
            root.navigationModel.openHeaderEditor = true
        } label: {
            Label {
                Text("Edit \(item?.name ?? "")", bundle: .module)
            } icon: {
                Image(systemName: "pencil")
            }
        }
        .keyboardShortcut("e", modifiers: [.command, .shift])
        .disabled(root.currentSelectedItemId == nil)
    }

    private var item: (any ItemDataAccessable)? {
        guard let selectedItemId = root.currentSelectedItemId else { return nil }
        return root.itemControllable.itemOrEmpty(for: selectedItemId)
    }
}

struct SpaceActionButton: View {
    let root: any ItemRootControllable
    let scenesManager: ScenesManager

    var body: some View {
        Button {
            if root.viewControllable.hasCustomSpaceAction {
                root.navigationModel.triggerSpaceAction = true
            } else {
                viewItem()
            }
        } label: {
            Label {
                labelText
            } icon: {
                Image(systemName: root.viewControllable.hasCustomSpaceAction ? "play.fill" : "eye")
            }
        }
        .keyboardShortcut(.return, modifiers: [.command, .shift])
        .disabled(root.currentSelectedItemId == nil)
    }

    private func viewItem() {
        let fileModel = root.openFileWindowModel
        guard fileModel.enabled else { return }
#if os(macOS) || os(visionOS)
        if let windowId = fileModel.windowId {
            scenesManager.openWindow(SceneId(rawValue: windowId), selection: WindowItemSelection(itemId: fileModel.itemId, entryId: fileModel.entryId))
            return
        }
#endif
        withAnimation { fileModel.showItem.toggle() }
    }

    private var labelText: Text {
        let name = item?.name ?? ""
        if root.viewControllable.hasCustomSpaceAction {
            return Text("\(root.configurable.module == .audio ? "Play" : "Roll") \(name)", bundle: .module)
        }
        return Text("View \(name)", bundle: .module)
    }

    private var item: (any ItemDataAccessable)? {
        guard let selectedItemId = root.currentSelectedItemId else { return nil }
        return root.itemControllable.itemOrEmpty(for: selectedItemId)
    }
}

struct ExportItemButton: View {
    let root: any ItemRootControllable

    var body: some View {
        Button {
            root.navigationModel.triggerExport = true
        } label: {
            Label {
                Text("Export \(item?.name ?? "")", bundle: .module)
            } icon: {
                Image(systemName: "square.and.arrow.up")
            }
        }
        .keyboardShortcut("e", modifiers: [.command, .control])
        .disabled(root.currentSelectedItemId == nil)
    }

    private var item: (any ItemDataAccessable)? {
        guard let selectedItemId = root.currentSelectedItemId else { return nil }
        return root.itemControllable.itemOrEmpty(for: selectedItemId)
    }
}

struct GroupEditorButton: View {
    let root: any ItemRootControllable

    var body: some View {
        Button {
            root.navigationModel.triggerGroupEditor = true
        } label: {
            Label {
                Text("Group Editor for \(item?.name ?? "")", bundle: .module)
            } icon: {
                Image(systemName: "long.text.page.and.pencil")
            }
        }
        .keyboardShortcut("g", modifiers: [.command, .control])
        .disabled(root.currentSelectedItemId == nil)
    }

    private var item: (any ItemDataAccessable)? {
        guard let selectedItemId = root.currentSelectedItemId else { return nil }
        return root.itemControllable.itemOrEmpty(for: selectedItemId)
    }
}

struct OpenFolderButton: View {
    let root: any ItemRootControllable

    var body: some View {
        Button {
            withAnimation { root.folderListControllable.openSelectedFolder() }
        } label: {
            Label {
                Text("Open Folder", bundle: .module)
            } icon: {
                Image(systemName: "chevron.down")
            }
        }
        .keyboardShortcut(.rightArrow, modifiers: [.command, .shift])
        .disabled(!root.folderListControllable.canOpenFolder(itemId: root.currentSelectedItemId))
    }
}

struct CloseFolderButton: View {
    let root: any ItemRootControllable

    var body: some View {
        Button {
            withAnimation { root.folderListControllable.closeParentFolder() }
        } label: {
            Label {
                Text("Close Parent Folder", bundle: .module)
            } icon: {
                Image(systemName: "chevron.up")
            }
        }
        .keyboardShortcut(.leftArrow, modifiers: [.command, .shift])
        .disabled(!root.folderListControllable.hasParentFolder(itemId: root.currentSelectedItemId))
    }
}

struct DuplicateItemButton: View {
    let root: any ItemRootControllable

    var body: some View {
        Button {
            if let item {
                Task {
                    await root.editControllable.duplicate(item: item)
                }
            }
        } label: {
            Label {
                Text("Duplicate \(item?.name ?? "")", bundle: .module)
            } icon: {
                Image(systemName: "doc.on.doc")
            }
        }
        .keyboardShortcut("D", modifiers: [.command, .shift])
        .disabled(root.currentSelectedItemId == nil)
    }

    private var item: (any ItemDataAccessable)? {
        guard let selectedItemId = root.currentSelectedItemId else { return nil }
        return root.itemControllable.itemOrEmpty(for: selectedItemId)
    }
}

struct BatchExtractionButton: View {
    let root: any ItemRootControllable

    var body: some View {
        Button {
            root.navigationModel.triggerBatchExtraction = true
        } label: {
            Label {
                Text("Extract Information for \(item?.name ?? "")", bundle: .module)
            } icon: {
                Image(systemName: "sparkles")
            }
        }
        .accessibilityHint(Text("Analyzes selected items with AI", bundle: .module))
        .disabled(root.currentSelectedItemId == nil)
    }

    private var item: (any ItemDataAccessable)? {
        guard let selectedItemId = root.currentSelectedItemId else { return nil }
        return root.itemControllable.itemOrEmpty(for: selectedItemId)
    }
}

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
        .keyboardShortcut("a", modifiers: [.command, .shift])
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

struct DeleteItemButton: View {
    let root: any ItemRootControllable

    var body: some View {
        Button(role: .destructive) {
            root.navigationModel.triggerDelete = true
        } label: {
            Label {
                Text("Delete \(item?.name ?? "")", bundle: .module)
            } icon: {
                Image(systemName: "trash")
            }
        }
        .keyboardShortcut(.delete, modifiers: .command)
        .disabled(root.currentSelectedItemId == nil)
    }

    private var item: (any ItemDataAccessable)? {
        guard let selectedItemId = root.currentSelectedItemId else { return nil }
        return root.itemControllable.itemOrEmpty(for: selectedItemId)
    }
}

#endif
