// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct SelectedAudioKey: FocusedValueKey {
    typealias Value = Binding<UUID>
}

extension FocusedValues {
    var selectedAudio: Binding<UUID>? {
        get { self[SelectedAudioKey.self] }
        set { self[SelectedAudioKey.self] = newValue }
    }
}

#if !os(tvOS)
public struct AudioCommands: Commands {
    public init(root: AudioRoot) {
        self.root = root
    }

    let root: AudioRoot
    @FocusedBinding(\.selectedModule) private var selectedModule: NetworkModules?

    public var body: some Commands {
#if os(macOS)
        CommandGroup(after: .windowArrangement) {
            AltLinkWindowCommandView(title: "Audio Link", networkModule: .audio, key: "6")
        }
#endif
        CommandGroup(after: .toolbar) {
            SwitchWindowButton()
        }
        CommandGroup(after: .newItem) {
            AddItemButton(root: root)
        }
        CommandGroup(before: .textEditing) {
            if selectedModule == .audio {
                DuplicateItemButton(root: root)
                Divider()
            }
        }
        CommandGroup(after: .undoRedo) {
            if selectedModule == .audio {
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
                    selectedModule <=> .audio
                    selectedGameModule <=> .audio
                }
            }
        } label: {
            Label { Text("Show Audios", bundle: .module) } icon: { Image(systemName: "eye") }
        }
        .keyboardShortcut("6", modifiers: [.command])
    }
}


struct AddItemButton: View {
    let root: AudioRoot
    
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
                    selectedModule <=> .audio
                }
                guard let listController = root.mainListController else { return }
                await listController.addNew()
            }
        } label: {
            Label { Text("New Audio", bundle: .module) } icon: { Image(systemName: "plus") }
        }
        .keyboardShortcut("6", modifiers: [.command, .control])
    }
}

struct DuplicateItemButton: View {
    let root: AudioRoot

    @FocusedBinding(\.selectedAudio) private var selectedAudio: UUID?

    var body: some View {
        Button {
            if let selectedAudio {
                Task {
                    await root.itemController.duplicate(model: ItemRowModel(itemId: selectedAudio, typeId: root.itemController.itemDataModel.networkModule))
                }
            }
        } label: {
            Text("Duplicate \(root.itemController.itemOrEmpty(for: selectedAudio ?? UUID()).name)", bundle: .module)
        }
        .keyboardShortcut("D", modifiers: [.command, .shift])
        .disabled(selectedAudio == nil)
    }
}

struct UndoButton: View {
    let root: AudioRoot
    
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
    let root: AudioRoot

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
