// @copyright André Trettin

import SwiftUI

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

#Preview { UndoButton(root: ItemRootController.fake) }
