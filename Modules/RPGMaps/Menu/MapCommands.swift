// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct SelectedMapKey: FocusedValueKey {
    typealias Value = Binding<UUID>
}

extension FocusedValues {
    var selectedMap: Binding<UUID>? {
        get { self[SelectedMapKey.self] }
        set { self[SelectedMapKey.self] = newValue }
    }
}

struct SelectedMapEntryKey: FocusedValueKey {
    typealias Value = Binding<UUID>
}

extension FocusedValues {
    var selectedMapEntry: Binding<UUID>? {
        get { self[SelectedMapEntryKey.self] }
        set { self[SelectedMapEntryKey.self] = newValue }
    }
}

#if !os(tvOS)
public struct MapCommands: Commands {
    public init(root: MapRootModel) {
        self.root = root
    }
    
    let root: MapRootModel
    @FocusedBinding(\.selectedModule) private var selectedModule: NetworkModules?
    
    public var body: some Commands {
#if os(macOS)
        CommandGroup(after: .windowArrangement) {
            AltLinkWindowCommandView(title: "Map Link", networkModule: .map, key: "5")
        }
#endif
        CommandGroup(after: .toolbar) {
            SwitchWindowButton()
        }
        CommandGroup(after: .newItem) {
            AddItemButton(root: root)
        }
        CommandGroup(before: .textEditing) {
            if selectedModule == .map {
                DuplicateItemButton(root: root)
                Divider()
            }
        }
        CommandGroup(after: .undoRedo) {
            if selectedModule == .map {
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
                    selectedModule <=> .map
                    selectedGameModule <=> .map
                }
            }
        } label: {
            Label { Text("Show Maps", bundle: .module) } icon: { Image(systemName: "eye") }
        }
        .keyboardShortcut("5", modifiers: [.command])
    }
}

struct AddItemButton: View {
    let root: MapRootModel
    
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
                    selectedModule <=> .map
                }
                guard let listController = root.mainListController else { return }
                await listController.addNew()
            }
        } label: {
            Label { Text("New Map", bundle: .module) } icon: { Image(systemName: "plus") }
        }
        .keyboardShortcut("5", modifiers: [.command, .control])
    }
}

struct DuplicateItemButton: View {
    let root: MapRootModel
    
    @FocusedBinding(\.selectedMap) private var selectedMap: UUID?
    
    var body: some View {
        Button {
            if let selectedMap {
                Task {
                    await root.itemController.duplicate(model: ItemRowModel(itemId: selectedMap, typeId: root.itemController.itemDataModel.networkModule))
                }
            }
        } label: {
            Text("Duplicate \(root.itemController.itemOrEmpty(for: selectedMap ?? UUID()).name)", bundle: .module)
        }
        .keyboardShortcut("D", modifiers: [.command, .shift])
        .disabled(selectedMap == nil)
    }
}

struct UndoButton: View {
    let root: MapRootModel
    
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
    let root: MapRootModel

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
