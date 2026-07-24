// @copyright André Trettin

import SwiftUI

@MainActor
enum ItemPrimaryAction {
    static func canPerform(
        root: any ItemRootControllable,
        itemId: UUID? = nil
    ) -> Bool {
        (itemId ?? root.currentSelectedItemId) != nil
            && (root.viewControllable.hasCustomSpaceAction
                || root.openFileWindowModel.enabled)
    }

    static func perform(
        root: any ItemRootControllable,
        scenesManager: ScenesManager,
        itemId: UUID? = nil
    ) {
        guard let selectedItemId = itemId ?? root.currentSelectedItemId else { return }

        if root.viewControllable.hasCustomSpaceAction {
            root.navigationModel.triggerSpaceAction = true
            return
        }

        let fileModel = root.openFileWindowModel
        guard fileModel.enabled else { return }
        fileModel.itemId = selectedItemId
        fileModel.entryId = nil

#if os(macOS) || os(visionOS)
        if let windowId = fileModel.windowId {
            scenesManager.openWindow(
                SceneId(rawValue: windowId),
                selection: WindowItemSelection(itemId: selectedItemId)
            )
            return
        }
#endif
        withAnimation {
            fileModel.showItem.toggle()
        }
    }
}
