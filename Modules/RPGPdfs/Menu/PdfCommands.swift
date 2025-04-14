// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct SelectedPdfKey: FocusedValueKey {
    typealias Value = Binding<UUID>
}

extension FocusedValues {
    var selectedPdf: Binding<UUID>? {
        get { self[SelectedPdfKey.self] }
        set { self[SelectedPdfKey.self] = newValue }
    }
}

#if !os(tvOS)
public struct PdfCommands: Commands {
    public init(root: PdfRoot) {
        self.root = root
    }

    let root: PdfRoot
    @FocusedBinding(\.selectedModule) private var selectedModule: NetworkModules?

    public var body: some Commands {
#if os(macOS)
        CommandGroup(after: .windowArrangement) {
            LinkWindowCommandView(title: "Pdf Link", networkModule: .pdf, key: "3")
        }
#endif
        CommandGroup(after: .toolbar) {
            SwitchWindowButton()
        }
        CommandGroup(after: .newItem) {
            AddItemButton(root: root)
        }
        CommandGroup(before: .textEditing) {
            if selectedModule == .pdf {
                DuplicateItemButton(root: root.itemController)
                Divider()
            }
        }
        CommandGroup(after: .undoRedo) {
            if selectedModule == .pdf {
                UndoButton(root: root)
                RedoButton(root: root)
            }
        }
    }
}

struct SwitchWindowButton: View {
    @Environment(\.openWindow) private var openWindow
    @FocusedBinding(\.selectedModule) private var selectedModule: NetworkModules?
    @FocusedBinding(\.selectedGameModule) private var selectedGameModule: NetworkModules?
    
    var body: some View {
        Button {
#if os(macOS)
            withAnimation {
                openWindow(id: WindowIdentifier.editor.rawValue)
            }
#endif
            Task { @MainActor in
                try await Task.sleep(for: .seconds(0.1))
                withAnimation {
                    selectedModule <=> .pdf
                    selectedGameModule <=> .pdf
                }
            }
        } label: {
            Label { Text("Show Pdfs", bundle: .module) } icon: { Image(systemName: "eye") }
        }
        .keyboardShortcut("3", modifiers: [.command])
    }
}

struct AddItemButton: View {
    let root: PdfRoot
    
    @Environment(\.openWindow) private var openWindow
    @FocusedBinding(\.selectedModule) private var selectedModule: NetworkModules?

    var body: some View {
        Button {
#if os(macOS)
            withAnimation {
                openWindow(id: WindowIdentifier.editor.rawValue)
            }
#endif

            Task { @MainActor in
                try await Task.sleep(for: .seconds(0.1))
                withAnimation {
                    selectedModule <=> .pdf
                }
                guard let listController = root.mainListController else { return }
                await listController.addNew()
            }
        } label: {
            Label { Text("New Pdf", bundle: .module) } icon: { Image(systemName: "plus") }
        }
        .keyboardShortcut("3", modifiers: [.command, .control])
    }
}

struct DuplicateItemButton: View {
    let root: ItemController

    @FocusedBinding(\.selectedPdf) private var selectedPdf: UUID?

    var body: some View {
        Button {
            if let selectedPdf {
                Task {
                    await root.duplicate(model: ItemRowModel(itemId: selectedPdf, typeId: root.itemDataModel.networkModule))
                }
            }
        } label: {
            Text("Duplicate \(root.itemOrEmpty(for: selectedPdf ?? UUID()).name)", bundle: .module)
        }
        .keyboardShortcut("D", modifiers: [.command, .shift])
        .disabled(selectedPdf == nil)
    }
}

struct UndoButton: View {
    let root: PdfRoot
    
    var body: some View {
        Button {
            withAnimation { root.editController(type: .main).undo() }
        } label: {
            Text("Undo \(root.editController(type: .main).undoTitle)", bundle: .module)
        }
        .keyboardShortcut("Z", modifiers: [.command])
        .disabled(!root.editController(type: .main).canUndo)
    }
}

struct RedoButton: View {
    let root: PdfRoot

    var body: some View {
        Button {
            withAnimation { root.editController(type: .main).redo() }
        } label: {
            Text("Redo \(root.editController(type: .main).redoTitle)", bundle: .module)
        }
        .keyboardShortcut("Z", modifiers: [.command, .shift])
        .disabled(!root.editController(type: .main).canRedo)
    }
}

#endif
