// @copyright André Trettin

import Foundation

@MainActor
struct ContextMenuMultiController {
    let editController: any EditControllable
    let itemController: any ItemControllable
    let listModel: FolderListModel
    
    var collectionIcon: String {
        itemController.collectionCategory.icon
    }
    
    func selection(currentSelected: UUID?) -> [UUID] {
        guard let currentSelected else { return listModel.selectionItemIds }
        return [currentSelected]
    }
    

    func parentItem(currentSelected: UUID?) -> (any ItemDataAccessible)? {
        guard let selectedId = selection(currentSelected: currentSelected).first, let parentId = itemController.itemSync(for: selectedId)?.parentId else { return nil }
        return itemController.itemSync(for: parentId)
    }
    
    func hasDifferentFolders(for parent: (any ItemDataAccessible)?) -> Bool {
        guard let parent, parent.isFolder else { return false }
        return parent.parentId != nil
    }
    
    func itemName(currentSelected: UUID?) -> String {
        let selection = selection(currentSelected: currentSelected)
        guard let itemId = selection.first, let model = itemController.itemSync(for: itemId) else { return "" }
        if selection.count > 1 {
            return "\(model.name) and \(selection.count - 1) more"
        } else {
            return model.name
        }
    }
    
    @MainActor func duplicateItem(currentSelected: UUID?) {
        editController.duplicateIgnoringRepeats(itemIds: selection(currentSelected: currentSelected))
    }
    
    func deleteItem(currentSelected: UUID?) -> [ItemRowModel] {
        let removed = listModel.deleteItems(ids: selection(currentSelected: currentSelected))
        for item in removed {
            editController.removeFromEditors(itemId: item.itemId)
        }
        return removed
    }
    
    func exportItem(currentSelected: UUID?) -> any NavigationDestination {
        let selection = selection(currentSelected: currentSelected)
        return InternalRoute.export(ids: selection)
    }
    
    func groupEditor(currentSelected: UUID?) -> any NavigationDestination {
        let selection = selection(currentSelected: currentSelected)
        return InternalRoute.groupEditor(ids: selection)
    }
    
    /// The folders (`isFolder`) or collections the selection can be placed in: those next to
    /// the first selected item.
    func placementTargets(currentSelected: UUID?, isFolder: Bool) -> [FolderRepresentable] {
        let selection = selection(currentSelected: currentSelected)
        guard let itemId = selection.first, let model = itemController.itemSync(for: itemId) else { return [] }
        return itemController.collections(isFolder: isFolder, in: model.parentId).map {
            FolderRepresentable(id: $0.id, name: $0.name)
        }
    }

    /// Whether `placementTargets(currentSelected:isFolder:)` would list anything.
    /// See CODE_AUDIT_Folder §7.4.
    func hasPlacementTargets(currentSelected: UUID?, isFolder: Bool) -> Bool {
        let selection = selection(currentSelected: currentSelected)
        guard let itemId = selection.first, let model = itemController.itemSync(for: itemId) else { return false }
        return itemController.hasCollections(isFolder: isFolder, in: model.parentId)
    }

    /// Moves the selection into a folder or adds it to a collection; `addItem(itemId:parentId:)`
    /// decides which by the target's category. Move and Add had two identical copies.
    /// See CODE_AUDIT_Folder §9.7.
    func place(currentSelected: UUID?, in target: FolderRepresentable) {
        for itemId in selection(currentSelected: currentSelected) {
            guard let model = itemController.itemSync(for: itemId) else { continue }
            editController.addItem(itemId: model.id, parentId: target.id)
        }
        openTargetFolder(target)
    }

    /// A moved item leaves its row, so a closed target folder is opened to show where it went.
    /// Only the row's open state is set: the list refresh that follows rebuilds the folder with
    /// its children. A collection keeps the item in the list as well and stays as it is.
    private func openTargetFolder(_ target: FolderRepresentable) {
        guard itemController.itemSync(for: target.id)?.isFolder == true,
              let row = listModel.row(itemId: target.id), !row.isOpen else { return }
        row.isOpen = true
        row.lastIsOpen = true
        row.wasExplicitlyClosed = false
    }

    func removeItemsFromFolder(currentSelected: UUID?, parentId: UUID?, oneUp: Bool) {
        guard let parentId else { return }
        let selection = selection(currentSelected: currentSelected)
        for itemId in selection {
            editController.remove(itemId: itemId, parentId: parentId, oneUp: oneUp)
        }
    }
}

extension ItemRootControllable {
    @MainActor var menuController: ContextMenuMultiController {
        ContextMenuMultiController(editController: editControllable, itemController: itemControllable, listModel: folderListControllable.listModel)
    }
}
