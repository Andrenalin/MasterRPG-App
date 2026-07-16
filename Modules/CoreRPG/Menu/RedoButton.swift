// @copyright André Trettin

import SwiftUI

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

#Preview { RedoButton(root: ItemRootController.fake) }
