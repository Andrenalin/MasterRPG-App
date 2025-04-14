// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct SelectedDiceKey: FocusedValueKey {
    typealias Value = Binding<UUID>
}

extension FocusedValues {
    var selectedDice: Binding<UUID>? {
        get { self[SelectedDiceKey.self] }
        set { self[SelectedDiceKey.self] = newValue }
    }
}

#if !os(tvOS)
public struct DiceCommands: Commands {
    public init(root: DiceRoot) {
        self.root = root
    }

    let root: DiceRoot
    @FocusedBinding(\.selectedModule) private var selectedModule: NetworkModules?

    public var body: some Commands {
#if os(macOS)
        CommandGroup(after: .windowArrangement) {
            LinkWindowCommandView(title: "\(root.itemController.itemDataModel.networkModule.title) Link", networkModule: root.itemController.itemDataModel.networkModule, key: "7")
        }
#endif
        CommandGroup(after: .toolbar) {
            SwitchWindowButton()
        }
        CommandGroup(after: .newItem) {
            AddItemButton(root: root)
        }
        CommandGroup(before: .textEditing) {
            if selectedModule == .dice {
                DuplicateItemButton(root: root)
                Divider()
            }
        }
        CommandGroup(after: .undoRedo) {
            if selectedModule == .dice {
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
                try await Task.sleep(for: .seconds(0.2))
                withAnimation {
                    selectedModule <=> .dice
                    selectedGameModule <=> .dice
                }
            }
        } label: {
            Label { Text("Show Dice", bundle: .module) } icon: { Image(systemName: "eye") }
        }
        .keyboardShortcut("7", modifiers: [.command])
    }
}

struct AddItemButton: View {
    let root: DiceRoot
    
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
                    selectedModule <=> .dice
                }
                guard let listController = root.mainListController else { return }
                await listController.addNew()
            }
        } label: {
            Label { Text("New Dice", bundle: .module) } icon: { Image(systemName: "plus") }
        }
        .keyboardShortcut("7", modifiers: [.command, .control])
    }
}

struct DuplicateItemButton: View {
    let root: DiceRoot

    @FocusedBinding(\.selectedDice) private var selectedDice: UUID?

    var body: some View {
        Button {
            if let selectedDice {
                Task {
                    await root.itemController.duplicate(model: ItemRowModel(itemId: selectedDice, typeId: root.itemController.itemDataModel.networkModule))
                }
            }
        } label: {
            Text("Duplicate \(root.itemController.itemOrEmpty(for: selectedDice ?? UUID()).name)", bundle: .module)
        }
        .keyboardShortcut("D", modifiers: [.command, .shift])
        .disabled(selectedDice == nil)
    }
}

struct UndoButton: View {
    let root: DiceRoot
    
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
    let root: DiceRoot

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
