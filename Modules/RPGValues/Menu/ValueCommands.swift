// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct SelectedValueKey: FocusedValueKey {
    typealias Value = Binding<UUID>
}

extension FocusedValues {
    var selectedValue: Binding<UUID>? {
        get { self[SelectedValueKey.self] }
        set { self[SelectedValueKey.self] = newValue }
    }
}

struct SelectedValueEntryKey: FocusedValueKey {
    typealias Value = Binding<UUID>
}

extension FocusedValues {
    var selectedValueEntry: Binding<UUID>? {
        get { self[SelectedValueEntryKey.self] }
        set { self[SelectedValueEntryKey.self] = newValue }
    }
}

#if !os(tvOS)
public struct ValueCommands: Commands {
    public init(root: CharacterRootModel) {
        self.root = root
    }

    let root: CharacterRootModel
    @FocusedBinding(\.selectedModule) private var selectedModule: NetworkModules?

    public var body: some Commands {
#if os(macOS)
        CommandGroup(after: .windowArrangement) {
            AltLinkWindowCommandView(title: "Character Link", networkModule: .value, key: "2")
        }
#endif
        CommandGroup(after: .toolbar) {
            SwitchWindowButton()
        }
        CommandGroup(after: .newItem) {
            Divider()
            AddItemButton(root: root)
        }
        CommandGroup(before: .textEditing) {
            if selectedModule == .value {
                DuplicateItemButton(store: root.itemController)
                Divider()
            }
        }
        CommandGroup(after: .undoRedo) {
            if selectedModule == .value {
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
                    selectedModule <=> .value
                    selectedGameModule <=> .value
                }
            }
        } label: {
            Label { Text("Show Charactere", bundle: .module) } icon: { Image(systemName: "eye") }
        }
        .keyboardShortcut("2", modifiers: [.command])
    }
}

struct AddItemButton: View {
    let root: CharacterRootModel
    
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
                    selectedModule <=> .value
                }
                guard let listController = root.mainListController else { return }
                await listController.addNew()
            }
        } label: {
            Label { Text("New Character", bundle: .module) } icon: { Image(systemName: "plus") }
        }
        .keyboardShortcut("2", modifiers: [.command, .control])
    }
}


struct DuplicateItemButton: View {
    let store: ItemController

    @FocusedBinding(\.selectedValue) private var selectedValue: UUID?

    var body: some View {
        Button {
            if let selectedValue {
                Task {
                    await store.duplicate(model: ItemRowModel(itemId: selectedValue, typeId: store.itemDataModel.networkModule))
                }
            }
        } label: {
            Text("Duplicate \(store.itemOrEmpty(for: selectedValue ?? UUID()).name)", bundle: .module)
        }
        .keyboardShortcut("D", modifiers: [.command, .shift])
        .disabled(selectedValue == nil)
    }
}

struct UndoButton: View {
    let root: CharacterRootModel
    
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
    let root: CharacterRootModel

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
