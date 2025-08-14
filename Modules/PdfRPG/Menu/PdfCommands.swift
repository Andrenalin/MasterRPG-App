// @copyright André Trettin

import CoreRPG
import SwiftData
import SwiftUI
import CoreExternalRPG

#if !os(tvOS)
public struct PdfCommands: Commands {
    public init(root: PdfRootModel, navigator: Navigator) {
        self.root = root
        self.navigator = navigator
    }
    
    let root: PdfRootModel
    let navigator: Navigator
    @FocusedBinding(\.selectedModule) private var selectedModule: NetworkModules?

    public var body: some Commands {
//#if os(macOS)
//        CommandGroup(after: .windowArrangement) {
//            LinkWindowCommandView(title: "Photo Link", networkModule: .photo, key: "3")
//        }
//#endif
        CommandGroup(after: .toolbar) {
            NavigateButton(navigator: navigator)
        }
        CommandGroup(after: .newItem) {
            AddItemButton(root: root, navigator: navigator)
        }
        CommandGroup(before: .textEditing) {
            if selectedModule == PdfDataModel.typeId {
                DuplicateItemButton(root: root)
                Divider()
            }
        }
        CommandGroup(before: .sidebar) {
            if selectedModule == PdfDataModel.typeId {
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
            navigator.perform(route: KnownRoutes.pdfs(nil, nil))
        } label: {
            Label { Text("Show Pdfs", bundle: .module) } icon: { Image(systemName: "eye") }
        }
        .keyboardShortcut("3", modifiers: [.command])
    }
}

struct AddItemButton: View {
    let root: PdfRootModel
    let navigator: Navigator

    var body: some View {
        Button {
            let item = root.editController.addNew(modelContext: root.modelContext, type: .item)
            navigator.perform(route: KnownRoutes.pdfs(item.id, nil))
        } label: {
            Label { Text("New Pdf", bundle: .module) } icon: { Image(systemName: "plus") }
        }
        .keyboardShortcut("3", modifiers: [.command, .control])
    }
}

struct DuplicateItemButton: View {
    let root: PdfRootModel

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

    var model: PdfDataModel? {
        guard let selectedItem = root.currentSelectedItemId else { return nil }
        return root.itemController.modelSync(for: selectedItem)
    }
}

#endif
