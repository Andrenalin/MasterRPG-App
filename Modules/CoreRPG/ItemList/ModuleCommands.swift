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
            let item = root.editControllable.addNew(modelContext: root.itemControllable.container.mainContext, module: root.module, type: .item)
            navigator.perform(route: KnownRoutes.route(module: root.module, itemId: item.id, entryId: nil))
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
            if let model {
                root.editControllable.duplicate(model: model)
            }
        } label: {
            Text("Duplicate \(model?.name ?? "")", bundle: .module)
        }
        .keyboardShortcut("D", modifiers: [.command, .shift])
        .disabled(root.currentSelectedItemId == nil)
    }

    var model: ItemDataModel? {
        guard let selectedItemId = root.currentSelectedItemId else { return nil }
        return root.itemControllable.modelSync(for: selectedItemId)
    }
}

#endif
