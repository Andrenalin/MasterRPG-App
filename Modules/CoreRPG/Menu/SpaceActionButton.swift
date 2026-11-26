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
        // Not in selection mode: Return toggles the keyboard row's check there (handled by the
        // list), and this command would take the key first.
        .keyboardShortcut(root.folderListControllable.listDisplayModel.isSelectionMode ? nil : KeyboardShortcut(.return, modifiers: []))
        .disabled(!isListFocused || !ItemPrimaryAction.canPerform(root: root))
    }

    private var labelText: Text {
        let name = item?.name ?? ""
        if root.viewControllable.hasCustomSpaceAction {
            let isAudio = root.configurable.module == .audio
            return .itemMenuTitle(
                name: name,
                plain: isAudio ? "Play" : "Roll",
                named: "\(isAudio ? "Play" : "Roll") \(name)"
            )
        }
        // "Show", not "View": "View" is the noun ("Ansicht") without a name.
        return .itemMenuTitle(name: name, plain: "Show", named: "View \(name)")
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
