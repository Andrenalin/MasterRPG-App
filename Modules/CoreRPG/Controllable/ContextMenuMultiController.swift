// @copyright André Trettin

import Foundation

#if os(macOS)
import AppKit
#elseif !os(tvOS)
import UIKit
#endif

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
    
    func selectionId(currentSelected: UUID?) -> [UUID] {
        guard let currentSelected else { return listModel.selection }
        return listModel.ids(selectedItemIds: [currentSelected])
    }
    
    func parentItem(currentSelected: UUID?) -> (any ItemDataAccessible)? {
        guard let selectedId = selection(currentSelected: currentSelected).first, let parentId = itemController.itemSync(for: selectedId)?.parentId else { return nil }
        return itemController.itemSync(for: parentId)
    }
    
    func hasDifferentFolders(for parent: (any ItemDataAccessible)?) -> Bool {
        guard let parent, parent.isFolder else { return false }
        return parent.parentId != nil
    }
    
    func itemCategory(currentSelected: UUID?) -> ItemListCategory {
        let selection = selection(currentSelected: currentSelected)
        guard let itemId = selection.first, let model = itemController.itemSync(for: itemId) else { return .entry }
        if selection.count > 1 {
            return .entry
        } else {
            return model.category
        }
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
    
    @MainActor func duplicateItem(currentSelected: UUID?) async {
        let selection = selection(currentSelected: currentSelected)
        for itemId in selection {
            guard let item = itemController.itemSync(for: itemId) else { continue }
            await editController.duplicate(item: item)
        }
    }
    
    func deleteItem(currentSelected: UUID?) -> [ItemRowModel] {
        let removed = listModel.deleteItems(ids: selectionId(currentSelected: currentSelected))
        for item in removed {
            editController.removeFromEditors(itemId: item.itemId)
        }
        return removed
    }
    
    func exportItem(currentSelected: UUID?) -> any NavigationDestination {
        let selection = selection(currentSelected: currentSelected)
        return InternalRoute.export(ids: selection)
    }
    
    func generateLink(currentSelected: UUID?) {
        let selection = self.selection(currentSelected: currentSelected)
        
        let linkText = selection.compactMap { id -> String? in
            guard let model = itemController.itemSync(for: id) else { return nil }
            return model.url(linkNumber: 0)
        }.joined(separator: ", ")
        
#if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(linkText, forType: .string)
#elseif !os(tvOS)
        let pasteboard = UIPasteboard.general
        pasteboard.string = linkText
#endif
    }
    
    func groupEditor(currentSelected: UUID?) -> any NavigationDestination {
        let selection = selection(currentSelected: currentSelected)
        return InternalRoute.groupEditor(ids: selection)
    }
    
    func folderItems(currentSelected: UUID?) -> [FolderRepresentable] {
        let selection = selection(currentSelected: currentSelected)
        guard let itemId = selection.first, let model = itemController.itemSync(for: itemId) else { return [] }
        let folders = itemController.collections(isFolder: true, in: model.parentId)
        return folders.map { FolderRepresentable(id: $0.id, name: $0.name) }
    }
    
    func moveItem(currentSelected: UUID?, to folder: FolderRepresentable) {
        let selection = selection(currentSelected: currentSelected)
        for itemId in selection {
            guard let model = itemController.itemSync(for: itemId) else { continue }
            editController.addItem(itemId: model.id, parentId: folder.id)
        }
    }
    
    func collectionItems(currentSelected: UUID?) -> [FolderRepresentable] {
        let selection = selection(currentSelected: currentSelected)
        guard let itemId = selection.first, let model = itemController.itemSync(for: itemId) else { return [] }
        let folders = itemController.collections(isFolder: false, in: model.parentId)
        return folders.map { FolderRepresentable(id: $0.id, name: $0.name) }
    }
    
    func addItem(currentSelected: UUID?, to folder: FolderRepresentable) {
        let selection = selection(currentSelected: currentSelected)
        for itemId in selection {
            guard let model = itemController.itemSync(for: itemId) else { continue }
            editController.addItem(itemId: model.id, parentId: folder.id)
        }
    }
    
    func removeItemsFromFolder(currentSelected: UUID?, parentId: UUID?, oneUp: Bool) {
        guard let parentId else { return }
        let selection = selection(currentSelected: currentSelected)
        for itemId in selection {
            editController.remove(itemId: itemId, parentId: parentId, oneUp: oneUp)
        }
    }
}
