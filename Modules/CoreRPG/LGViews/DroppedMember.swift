// @copyright André Trettin

import SwiftUI

/// Files an item as a member of the open folder or collection after a drop: adds it, runs a
/// fresh detail search and records the organizing tip. Shared by the list rows and the "Drop
/// here" placeholder. See CODE_AUDIT_26 §9.17.
@MainActor
func addDroppedMember(itemId: UUID, to parentId: UUID, root: any ItemRootControllable, listController: any FolderListControllable) {
    withAnimation {
        root.editControllable.addItem(itemId: itemId, parentId: parentId)
        listController.scheduleDetailSearch()
        // A fresh search, not `resetFilter()`, which rebuilt from stale results and left the
        // moved item at root as well. See CODE_AUDIT_Folder §5.29.
        root.folderListControllable.update(debounce: false)
        Task {
            await MasterRPGTips.donateContentOrganized()
        }
    }
}
