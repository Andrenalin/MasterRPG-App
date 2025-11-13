// @copyright André Trettin

import CoreExternalRPG
import SwiftData
import SwiftUI

#if !os(tvOS)
public struct ModuleCommands: Commands {
    public init(root: any ItemRootControllable, navigator: Navigator, key: AKKeyEquivalent) {
        self.root = root
        self.navigator = navigator
        self.key = key
    }
    
    let root: any ItemRootControllable
    let navigator: Navigator
    let key: AKKeyEquivalent
    
    @FocusedBinding(\.selectedModule) private var selectedModule: NetworkModules?

    public var body: some Commands {
        CommandGroup(after: .windowArrangement) {
            LinkWindowCommandView(networkModule: root.module, key: key)
        }
        CommandGroup(after: .toolbar) {
            NavigateButton(root: root, navigator: navigator, key: key)
        }
        CommandGroup(after: .newItem) {
            AddItemButton(root: root, navigator: navigator, key: key)
        }
        CommandGroup(before: .textEditing) {
            if selectedModule == root.module {
                DuplicateItemButton(root: root)
                Divider()
            }
        }
        CommandGroup(after: .undoRedo) {
            if selectedModule == root.module {
                UndoButton(root: root)
                RedoButton(root: root)
            }
        }
        CommandGroup(before: .sidebar) {
            if selectedModule == root.module {
                MenuDisplayModeToggle(listDisplayModel: root.listDisplayModel, showSelectionButton: true)
                Divider()
            }
        }
    }
}

struct NavigateButton: View {
    let root: any ItemRootControllable
    let navigator: Navigator
    let key: AKKeyEquivalent

    var body: some View {
        Button {
            navigator.perform(route: KnownRoutes.route(module: root.module, itemId: nil, entryId: nil))
        } label: {
            Label { Text("Show \(root.module.title)", bundle: .module) } icon: { Image(systemName: "eye") }
        }
        .keyboardShortcut(key, modifiers: [.command])
    }
}

struct AddItemButton: View {
    let root: any ItemRootControllable
    let navigator: Navigator
    let key: AKKeyEquivalent

    var body: some View {
        Button {
            Task {
                guard let item = await root.editControllable.addNew(type: .item) else { return }
                navigator.perform(route: KnownRoutes.route(module: root.module, itemId: item.id, entryId: nil))
            }
        } label: {
            Label { Text("New \(root.module.title)", bundle: .module) } icon: { Image(systemName: "plus") }
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

struct UndoButton: View {
    let root: any ItemRootControllable
    
    var body: some View {
        Button {
            withAnimation { root.editControllable.undo() }
        } label: {
            Label {
                Text("Undo \(root.editControllable.undoTitle)", bundle: .module)
            } icon: {
                Image(systemName: "arrow.uturn.backward")
            }
        }
        .keyboardShortcut("Z", modifiers: [.command])
        .disabled(!root.editControllable.canUndo)
    }
}

struct RedoButton: View {
    let root: any ItemRootControllable

    var body: some View {
        Button {
            withAnimation { root.editControllable.redo() }
        } label: {
            Label {
                Text("Redo \(root.editControllable.redoTitle)", bundle: .module)
            } icon: {
                Image(systemName: "arrow.uturn.forward")
            }
        }
        .keyboardShortcut("Z", modifiers: [.command, .shift])
        .disabled(!root.editControllable.canRedo)
    }
}

#endif
