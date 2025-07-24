// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI
import CoreExternalRPG

extension FocusedValues {
    @Entry var selectedItem: Binding<UUID>?
}

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
            if selectedModule == SpaceDataModel.typeId {
                DuplicateItemButton(root: root)
                Divider()
            }
        }
//        CommandGroup(after: .undoRedo) {
//            if selectedModule == .photo {
//                UndoButton(root: root)
//                RedoButton(root: root)
//            }
//        }
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
        .keyboardShortcut("8", modifiers: [.command])
    }
}

struct AddItemButton: View {
    let root: SpaceRootModel
    let navigator: Navigator

    var body: some View {
        Button {
            let item = root.editController.addNew(modelContext: root.modelContext)
            navigator.perform(route: KnownRoutes.spaces(item.id, nil))
        } label: {
            Label { Text("New Space", bundle: .module) } icon: { Image(systemName: "plus") }
        }
        .keyboardShortcut("8", modifiers: [.command, .control])
    }
}

struct DuplicateItemButton: View {
    let root: SpaceRootModel

    @FocusedBinding(\.selectedItem) private var selectedItem: UUID?

    var body: some View {
        Button {
            if let model {
                root.editController.duplicate(model: model)
            }
        } label: {
            Text("Duplicate \(model?.name ?? "")", bundle: .module)
        }
        .keyboardShortcut("D", modifiers: [.command, .shift])
        .disabled(selectedItem == nil)
    }

    var model: SpaceDataModel? {
        guard let selectedItem else { return nil }
        return root.itemController.modelSync(for: selectedItem)
    }
}

//struct UndoButton: View {
//    let root: PhotoRoot
//    
//    var body: some View {
//        Button {
//            withAnimation { root.editController(type: .main).undo() }
//        } label: {
//            Text("Undo \(root.editController(type: .main).undoTitle)", bundle: .module)
//        }
//        .keyboardShortcut("Z", modifiers: [.command])
//        .disabled(!root.editController(type: .main).canUndo)
//    }
//}
//
//struct RedoButton: View {
//    let root: PhotoRoot
//
//    var body: some View {
//        Button {
//            withAnimation { root.editController(type: .main).redo() }
//        } label: {
//            Text("Redo \(root.editController(type: .main).redoTitle)", bundle: .module)
//        }
//        .keyboardShortcut("Z", modifiers: [.command, .shift])
//        .disabled(!root.editController(type: .main).canRedo)
//    }
//}

#endif
