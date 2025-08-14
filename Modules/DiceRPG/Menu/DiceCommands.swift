// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI
import CoreExternalRPG

#if !os(tvOS)
public struct DiceCommands: Commands {
    public init(root: DiceRootModel, navigator: Navigator) {
        self.root = root
        self.navigator = navigator
    }
    
    let root: DiceRootModel
    let navigator: Navigator
    @FocusedBinding(\.selectedModule) private var selectedModule: NetworkModules?

    public var body: some Commands {
//#if os(macOS)
//        CommandGroup(after: .windowArrangement) {
//            LinkWindowCommandView(title: "Photo Link", networkModule: .photo, key: "7")
//        }
//#endif
        CommandGroup(after: .toolbar) {
            NavigateButton(navigator: navigator)
        }
        CommandGroup(after: .newItem) {
            AddItemButton(root: root, navigator: navigator)
        }
        CommandGroup(before: .textEditing) {
            if selectedModule == DiceDataModel.typeId {
                DuplicateItemButton(root: root)
                Divider()
            }
        }
        CommandGroup(before: .sidebar) {
            if selectedModule == DiceDataModel.typeId {
                MenuDisplayModeToggle(listModel: root.listModel, showSelectionButton: true)
                Divider()
            }
        }
    }
}

struct NavigateButton: View {
    let navigator: Navigator

    var body: some View {
        Button {
            navigator.perform(route: KnownRoutes.dice(nil, nil))
        } label: {
            Label { Text("Show Dice", bundle: .module) } icon: { Image(systemName: "eye") }
        }
        .keyboardShortcut("7", modifiers: [.command])
    }
}

struct AddItemButton: View {
    let root: DiceRootModel
    let navigator: Navigator

    var body: some View {
        Button {
            let item = root.editController.addNew(modelContext: root.modelContext, type: .item)
            navigator.perform(route: KnownRoutes.dice(item.id, nil))
        } label: {
            Label { Text("New Dice", bundle: .module) } icon: { Image(systemName: "plus") }
        }
        .keyboardShortcut("7", modifiers: [.command, .control])
    }
}

struct DuplicateItemButton: View {
    let root: DiceRootModel

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

    var model: DiceDataModel? {
        guard let selectedItem = root.currentSelectedItemId else { return nil }
        return root.itemController.modelSync(for: selectedItem)
    }
}

#endif
