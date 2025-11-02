// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct SelectedPhotoKey: FocusedValueKey {
    typealias Value = Binding<UUID>
}

extension FocusedValues {
    var selectedPhoto: Binding<UUID>? {
        get { self[SelectedPhotoKey.self] }
        set { self[SelectedPhotoKey.self] = newValue }
    }
}

#if !os(tvOS)
public struct PhotoCommands: Commands {
    public init(root: PhotoRoot) {
        self.root = root
    }
    
    let root: PhotoRoot
    @FocusedBinding(\.selectedModule) private var selectedModule: NetworkModules?

    public var body: some Commands {
#if os(macOS)
        CommandGroup(after: .windowArrangement) {
            AltLinkWindowCommandView(title: "Photo Link", networkModule: .photo, key: "8")
        }
#endif
        CommandGroup(after: .toolbar) {
            SwitchWindowButton()
        }
        CommandGroup(after: .newItem) {
            AddItemButton(root: root)
        }
        CommandGroup(before: .textEditing) {
            if selectedModule == .photo {
                DuplicateItemButton(root: root)
                Divider()
            }
        }
        CommandGroup(after: .undoRedo) {
            if selectedModule == .photo {
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
                    selectedModule <=> .photo
                    selectedGameModule <=> .photo
                }
            }
        } label: {
            Label { Text("Show Photos", bundle: .module) } icon: { Image(systemName: "eye") }
        }
        .keyboardShortcut("8", modifiers: [.command])
    }
}

struct AddItemButton: View {
    let root: PhotoRoot
    
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
                    selectedModule <=> .photo
                }
                guard let listController = root.mainListController else { return }
                await listController.addNew()
            }
        } label: {
            Label { Text("New Photo", bundle: .module) } icon: { Image(systemName: "plus") }
        }
        .keyboardShortcut("8", modifiers: [.command, .control])
    }
}

struct DuplicateItemButton: View {
    let root: PhotoRoot

    @FocusedBinding(\.selectedPhoto) private var selectedPhoto: UUID?

    var body: some View {
        Button {
            if let selectedPhoto {
                Task {
                    await root.itemController.duplicate(model: ItemRowModel(itemId: selectedPhoto, typeId: root.itemController.itemDataModel.networkModule))
                }
            }
        } label: {
            Text("Duplicate \(root.itemController.itemOrEmpty(for: selectedPhoto ?? UUID()).name)", bundle: .module)
        }
        .keyboardShortcut("D", modifiers: [.command, .shift])
        .disabled(selectedPhoto == nil)
    }
}

struct UndoButton: View {
    let root: PhotoRoot
    
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
    let root: PhotoRoot

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
