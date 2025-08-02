// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI
import CoreExternalRPG

extension FocusedValues {
    @Entry var selectedItem: Binding<UUID>?
}

#if !os(tvOS)
public struct PhotoCommands: Commands {
    public init(root: PhotoRootModel, navigator: Navigator) {
        self.root = root
        self.navigator = navigator
    }
    
    let root: PhotoRootModel
    let navigator: Navigator
    @FocusedBinding(\.selectedModule) private var selectedModule: NetworkModules?

    public var body: some Commands {
//#if os(macOS)
//        CommandGroup(after: .windowArrangement) {
//            LinkWindowCommandView(title: "Photo Link", networkModule: .photo, key: "8")
//        }
//#endif
        CommandGroup(after: .toolbar) {
            NavigateButton(navigator: navigator)
        }
        CommandGroup(after: .newItem) {
            AddItemButton(root: root, navigator: navigator)
        }
        CommandGroup(before: .textEditing) {
            if selectedModule == PhotoDataModel.typeId {
                DuplicateItemButton(root: root)
                Divider()
            }
        }
        CommandGroup(before: .sidebar) {
            if selectedModule == PhotoDataModel.typeId {
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
            navigator.perform(route: KnownRoutes.photos(nil, nil))
        } label: {
            Label { Text("Show Photos", bundle: .module) } icon: { Image(systemName: "eye") }
        }
        .keyboardShortcut("8", modifiers: [.command])
    }
}

struct AddItemButton: View {
    let root: PhotoRootModel
    let navigator: Navigator

    var body: some View {
        Button {
            let item = root.editController.addNew(modelContext: root.modelContext, type: .item)
            navigator.perform(route: KnownRoutes.photos(item.id, nil))
        } label: {
            Label { Text("New Photo", bundle: .module) } icon: { Image(systemName: "plus") }
        }
        .keyboardShortcut("8", modifiers: [.command, .control])
    }
}

struct DuplicateItemButton: View {
    let root: PhotoRootModel

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

    var model: PhotoDataModel? {
        guard let selectedItem = root.currentSelectedItemId else { return nil }
        return root.itemController.modelSync(for: selectedItem)
    }
}

#endif
