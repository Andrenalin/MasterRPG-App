// @copyright André Trettin

import SwiftUI

public struct MenuUndoRedoButton: View {
    public init(root: any ItemRootControllable) {
        self.root = root
    }
    
    let root: any ItemRootControllable

    public var body: some View {
        ControlGroup {
            UndoButton(root: root)
            RedoButton(root: root)
        }
    }
}

struct UndoButton: View {
    let root: any ItemRootControllable
    
    var body: some View {
        Button {
            withAnimation { root.editControllable.undo() }
        } label: {
            Label {
                Text("Undo \(root.editControllable.undoTitle)", bundle: .module)
            } icon: {
                Image(systemName: "arrow.uturn.backward")
            }
        }
#if !os(tvOS)
        .keyboardShortcut("Z", modifiers: [.command])
#endif
        .disabled(!root.editControllable.canUndo)
    }
}

struct RedoButton: View {
    let root: any ItemRootControllable

    var body: some View {
        Button {
            withAnimation { root.editControllable.redo() }
        } label: {
            Label {
                Text("Redo \(root.editControllable.redoTitle)", bundle: .module)
            } icon: {
                Image(systemName: "arrow.uturn.forward")
            }
        }
#if !os(tvOS)
        .keyboardShortcut("Z", modifiers: [.command, .shift])
#endif
        .disabled(!root.editControllable.canRedo)
    }
}
