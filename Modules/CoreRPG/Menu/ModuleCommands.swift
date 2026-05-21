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

    public var body: some Commands {
        CommandGroup(after: .windowArrangement) {
            LinkWindowCommandView(networkModule: root.configurable.module, scenesManager: scenesManager, key: key)
        }
        CommandGroup(after: .toolbar) {
            NavigateButton(root: root, routeActions: routeActions, key: key)
        }
        CommandGroup(after: .newItem) {
            AddItemButton(root: root, routeActions: routeActions, key: key)
        }
        CommandGroup(before: .textEditing) {
            if selectedModule == root.configurable.module {
                DuplicateItemButton(root: root)
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
            if selectedModule == root.configurable.module {
                MenuDisplayModeToggle(listDisplayModel: root.listDisplayModel, showSelectionButton: true)
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
            Text("Duplicate \(item?.name ?? "")", bundle: .module)
        }
        .keyboardShortcut("D", modifiers: [.command, .shift])
        .disabled(root.currentSelectedItemId == nil)
    }

    var item: (any ItemDataAccessable)? {
        guard let selectedItemId = root.currentSelectedItemId else { return nil }
        return root.itemControllable.itemOrEmpty(for: selectedItemId)
    }
}

#endif
