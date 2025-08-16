// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI
import CoreExternalRPG

#if !os(tvOS)
public struct SpaceCommands: Commands {
    public init(root: SpaceRootModel, navigator: Navigator) {
        self.root = root
        self.navigator = navigator
    }
    
    let root: SpaceRootModel
    let navigator: Navigator
    @FocusedBinding(\.selectedModule) private var selectedModule: NetworkModules?

    public var body: some Commands {
        CommandGroup(after: .windowArrangement) {
            LinkWindowCommandView(networkModule: .space, key: "9")
        }
        CommandGroup(after: .toolbar) {
            NavigateButton(navigator: navigator)
        }
        CommandGroup(after: .newItem) {
            AddItemButton(root: root, navigator: navigator)
        }
        CommandGroup(before: .textEditing) {
            if selectedModule == SpaceDataModel.typeId {
                DuplicateItemButton(root: root)
                Divider()
            }
        }
        CommandGroup(before: .sidebar) {
            if selectedModule == SpaceDataModel.typeId {
                MenuDisplayModeToggle(listDisplayModel: root.listDisplayModel, showSelectionButton: true)
                Divider()
            }
        }
    }
}

struct NavigateButton: View {
    let navigator: Navigator

    var body: some View {
        Button {
            navigator.perform(route: KnownRoutes.spaces(nil, nil))
        } label: {
            Label { Text("Show Spaces", bundle: .module) } icon: { Image(systemName: "eye") }
        }
        .keyboardShortcut("9", modifiers: [.command])
    }
}

struct AddItemButton: View {
    let root: SpaceRootModel
    let navigator: Navigator

    var body: some View {
        Button {
            let item = root.editController.addNew(modelContext: root.modelContext, type: .item)
            navigator.perform(route: KnownRoutes.spaces(item.id, nil))
        } label: {
            Label { Text("New Space", bundle: .module) } icon: { Image(systemName: "plus") }
        }
        .keyboardShortcut("9", modifiers: [.command, .control])
    }
}

struct DuplicateItemButton: View {
    let root: SpaceRootModel

    var body: some View {
        Button {
            if let model {
                root.editController.duplicate(model: model)
            }
        } label: {
            Text("Duplicate \(model?.name ?? "")", bundle: .module)
        }
        .keyboardShortcut("D", modifiers: [.command, .shift])
        .disabled(root.currentSelectedItemId == nil)
    }

    var model: SpaceDataModel? {
        guard let selectedItem = root.currentSelectedItemId else { return nil }
        return root.itemController.modelSync(for: selectedItem)
    }
}

#endif
