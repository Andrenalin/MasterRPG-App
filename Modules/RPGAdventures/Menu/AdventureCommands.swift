// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct SelectedAdventureKey: FocusedValueKey {
    typealias Value = Binding<UUID>
}

extension FocusedValues {
    var selectedAdventure: Binding<UUID>? {
        get { self[SelectedAdventureKey.self] }
        set { self[SelectedAdventureKey.self] = newValue }
    }
}

struct SelectedAdventureEntryKey: FocusedValueKey {
    typealias Value = Binding<UUID>
}

extension FocusedValues {
    var selectedMapEntry: Binding<UUID>? {
        get { self[SelectedAdventureEntryKey.self] }
        set { self[SelectedAdventureEntryKey.self] = newValue }
    }
}

#if !os(tvOS)
public struct AdventureCommands: Commands {
    public init(root: AdventureRoot) {
        self.root = root
    }

    let root: AdventureRoot
    @FocusedBinding(\.selectedModule) private var selectedModule: NetworkModules?

    public var body: some Commands {
#if os(macOS)
        CommandGroup(after: .windowArrangement) {
            AltLinkWindowCommandView(title: "Adventure Link", networkModule: .adventure, key: "1")
        }
#endif
        CommandGroup(after: .toolbar) {
            SwitchWindowButton()
        }
        CommandGroup(after: .newItem) {
            AddItemButton(root: root)
        }
        CommandGroup(before: .textEditing) {
            if selectedModule == .adventure {
                DuplicateItemButton(root: root)
                Divider()
            }
        }
        CommandGroup(replacing: .undoRedo) {
            EmptyView()
        }
        CommandGroup(after: .undoRedo) {
            if selectedModule == .adventure {
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
                    selectedModule <=> .adventure
                    selectedGameModule <=> .adventure
                }
            }
        } label: {
            Label { Text("Show Adventures", bundle: .module) } icon: { Image(systemName: "eye") }
        }
        .keyboardShortcut("1", modifiers: [.command])
    }
}

struct AddItemButton: View {
    let root: AdventureRoot
    
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
                    selectedModule <=> .adventure
                }
                guard let listController = root.mainListController else { return }
                await listController.addNew()
            }
        } label: {
            Label { Text("New Adventure", bundle: .module) } icon: { Image(systemName: "plus") }
        }
        .keyboardShortcut("1", modifiers: [.command, .control])
    }
}

struct DuplicateItemButton: View {
    let root: AdventureRoot

    @FocusedBinding(\.selectedAdventure) private var selectedAdventure: UUID?

    var body: some View {
        Button {
            if let selectedAdventure {
                Task {
                    await root.itemController.duplicate(model: ItemRowModel(itemId: selectedAdventure, typeId: root.itemController.itemDataModel.networkModule))
                }
            }
        } label: {
            Text("Duplicate \(root.itemController.itemOrEmpty(for: selectedAdventure ?? UUID()).name)", bundle: .module)
        }
        .keyboardShortcut("D", modifiers: [.command, .shift])
        .disabled(selectedAdventure == nil)
    }
}

struct UndoButton: View {
    let root: AdventureRoot
    
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
    let root: AdventureRoot

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
