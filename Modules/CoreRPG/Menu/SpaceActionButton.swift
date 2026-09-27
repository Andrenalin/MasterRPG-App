// @copyright André Trettin

import SwiftUI

#if !os(tvOS)
struct SpaceActionButton: View {
    let root: any ItemRootControllable
    let scenesManager: ScenesManager
    var isListFocused = true

    var body: some View {
        Button {
            ItemPrimaryAction.perform(root: root, scenesManager: scenesManager)
        } label: {
            Label {
                labelText
            } icon: {
                Image(systemName: root.viewControllable.hasCustomSpaceAction ? "play.fill" : "eye")
            }
        }
        .keyboardShortcut(.return, modifiers: [])
        .disabled(!isListFocused || !ItemPrimaryAction.canPerform(root: root))
    }

    private var labelText: Text {
        let name = item?.name ?? ""
        if root.viewControllable.hasCustomSpaceAction {
            return Text("\(root.configurable.module == .audio ? "Play" : "Roll") \(name)", bundle: .module)
        }
        return Text("View \(name)", bundle: .module)
    }

    private var item: (any ItemDataAccessible)? {
        guard let selectedItemId = root.currentSelectedItemId else { return nil }
        return root.itemControllable.itemOrEmpty(for: selectedItemId)
    }
}

#Preview {
    SpaceActionButton(root: ItemRootController.fake, scenesManager: ScenesManager())
}
#endif
