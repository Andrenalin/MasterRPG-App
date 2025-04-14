// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct SelectedSpaceKey: FocusedValueKey {
    typealias Value = Binding<UUID>
}

extension FocusedValues {
    var selectedSpace: Binding<UUID>? {
        get { self[SelectedSpaceKey.self] }
        set { self[SelectedSpaceKey.self] = newValue }
    }
}

#if !os(tvOS)
public struct SpaceCommands: Commands {
    public init(root: SpaceRoot) {
        self.root = root
    }
    
    let root: SpaceRoot
    @FocusedBinding(\.selectedModule) private var selectedModule: NetworkModules?

    public var body: some Commands {
#if os(macOS)
        CommandGroup(after: .windowArrangement) {
            LinkWindowCommandView(title: "Space Link", networkModule: .space, key: "9")
        }
#endif
        CommandGroup(after: .toolbar) {
            SwitchWindowButton()
        }
        CommandGroup(after: .newItem) {
            AddItemButton(root: root)
        }
        CommandGroup(before: .textEditing) {
            if selectedModule == .space {
                DuplicateItemButton(root: root)
                Divider()
            }
        }
        CommandGroup(after: .undoRedo) {
            if selectedModule == .space {
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
                    selectedModule <=> .space
                    selectedGameModule <=> .space
                }
            }
        } label: {
            Label { Text("Show Spaces", bundle: .module) } icon: { Image(systemName: "eye") }
        }
        .keyboardShortcut("9", modifiers: [.command])
    }
}

struct AddItemButton: View {
    let root: SpaceRoot
    
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
                    selectedModule <=> .space
                }
                guard let listController = root.mainListController else { return }
                await listController.addNew()
            }
        } label: {
            Label { Text("New Space", bundle: .module) } icon: { Image(systemName: "plus") }
        }
        .keyboardShortcut("9", modifiers: [.command, .control])
    }
}

struct DuplicateItemButton: View {
    let root: SpaceRoot

    @FocusedBinding(\.selectedSpace) private var selectedSpace: UUID?

    var body: some View {
        Button {
            if let selectedSpace {
                Task {
                    await root.itemController.duplicate(model: ItemRowModel(itemId: selectedSpace, typeId: root.itemController.itemDataModel.networkModule))
                }
            }
        } label: {
            Text("Duplicate \(root.itemController.itemOrEmpty(for: selectedSpace ?? UUID()).name)", bundle: .module)
        }
        .keyboardShortcut("D", modifiers: [.command, .shift])
        .disabled(selectedSpace == nil)
    }
}

struct UndoButton: View {
    let root: SpaceRoot
    
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
    let root: SpaceRoot

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
