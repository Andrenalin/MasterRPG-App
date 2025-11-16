// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct SelectedTableKey: FocusedValueKey {
    typealias Value = Binding<UUID>
}

extension FocusedValues {
    var selectedTable: Binding<UUID>? {
        get { self[SelectedTableKey.self] }
        set { self[SelectedTableKey.self] = newValue }
    }
}

struct SelectedTableEntryKey: FocusedValueKey {
    typealias Value = Binding<UUID>
}

extension FocusedValues {
    var selectedTableEntry: Binding<UUID>? {
        get { self[SelectedTableEntryKey.self] }
        set { self[SelectedTableEntryKey.self] = newValue }
    }
}

#if !os(tvOS)
public struct TableCommands: Commands {
    public init(root: TableRootModel) {
        self.root = root
    }

    let root: TableRootModel
    @FocusedBinding(\.selectedModule) private var selectedModule: NetworkModules?

    public var body: some Commands {
#if os(macOS)
        CommandGroup(after: .windowArrangement) {
            AltLinkWindowCommandView(title: "Table Link", networkModule: .table, key: "4")
        }
#endif
        CommandGroup(after: .toolbar) {
            SwitchWindowButton()
        }
        CommandGroup(after: .newItem) {
            AddItemButton(root: root)
        }
        CommandGroup(before: .textEditing) {
            if selectedModule == .table {
                DuplicateItemButton(itemController: root.itemController)
                Divider()
            }
        }
        CommandGroup(after: .undoRedo) {
            if selectedModule == .table {
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
                    selectedModule <=> .table
                    selectedGameModule <=> .table
                }
            }
        } label: {
            Label { Text("Show Tables", bundle: .module) } icon: { Image(systemName: "eye") }
        }
        .keyboardShortcut("4", modifiers: [.command])
    }
}

struct AddItemButton: View {
    let root: TableRootModel
    
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
                    selectedModule <=> .table
                }
                guard let listController = root.mainListController else { return }
                await listController.addNew()
            }
        } label: {
            Label { Text("New Table", bundle: .module) } icon: { Image(systemName: "plus") }
        }
        .keyboardShortcut("4", modifiers: [.command, .control])
    }
}

struct DuplicateItemButton: View {
    let itemController: ItemController

    @FocusedBinding(\.selectedTable) private var selectedTable: UUID?

    var body: some View {
        Button {
            Task {
                if let selectedTable {
                    await itemController.duplicate(model: ItemRowModel(itemId: selectedTable, typeId: itemController.itemDataModel.networkModule))
                }
            }
        } label: {
            Text("Duplicate \(itemController.itemOrEmpty(for: selectedTable ?? UUID()).name)", bundle: .module)
        }
        .keyboardShortcut("D", modifiers: [.command, .shift])
        .disabled(selectedTable == nil)
    }
}

struct UndoButton: View {
    let root: TableRootModel
    
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
    let root: TableRootModel

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
