// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import Foundation
import SwiftData
#if os(macOS)
internal import AppKit
#else
internal import UIKit
#endif

@MainActor
struct ContextMenuMultiController: ItemListContextMenuControllable {
    let editController: EditController
    let itemController: OldItemController
    let listModel: OldListModel

    var collectionIcon: String = ItemListCategory.playlist.icon

    func selection(currentSelected: UUID?) -> [UUID] {
        guard let currentSelected else { return listModel.selectionItemIds }
        return [currentSelected]
    }

    func itemName(currentSelected: UUID?) -> String {
        let selection = selection(currentSelected: currentSelected)
        guard let itemId = selection.first, let model = itemController.modelSync(for: itemId) else { return "" }
        if selection.count > 1 {
            return "\(model.name) and \(selection.count - 1) more"
        } else {
            return model.name
        }
    }
    
    func duplicateItem(currentSelected: UUID?) {
        let selection = selection(currentSelected: currentSelected)
        for itemId in selection {
            guard let model = itemController.modelSync(for: itemId) else { continue }
            editController.duplicate(model: model)
        }
    }
    
    func deleteItem(currentSelected: UUID?) {
        let selection = selection(currentSelected: currentSelected)
        for itemId in selection {
            guard let model = itemController.modelSync(for: itemId) else { continue }
            editController.delete(model: model)
        }
    }
    
    func exportItem(currentSelected: UUID?) -> any NavigationDestination {
        let selection = selection(currentSelected: currentSelected)
        return InternalRoute.export(ids: selection)
    }
    
    func generateLink(currentSelected: UUID?) {
        let selection = selection(currentSelected: currentSelected)

        let linkText = selection.compactMap {
            guard let model = itemController.modelSync(for: $0) else { return nil }
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
    
    func folderItems(currentSelected: UUID?) -> [CoreRPG.FolderRepresentable] {
        let selection = selection(currentSelected: currentSelected)
        guard let itemId = selection.first, let model = itemController.modelSync(for: itemId) else { return [] }
        let folders = itemController.collections(isFolder: true, in: model.parentId)
        return folders.map { FolderRepresentable(id: $0.id, name: $0.name) }
    }
    
    func moveItem(currentSelected: UUID?, to folder: FolderRepresentable) {
        let selection = selection(currentSelected: currentSelected)
        guard let folder = itemController.modelSync(for: folder.id) else { return }
        for itemId in selection {
            guard let model = itemController.modelSync(for: itemId) else { continue }
            editController.addItem(itemId: model.id, in: folder, folderId: folder.id)
        }
    }
    
    func collectionItems(currentSelected: UUID?) -> [FolderRepresentable] {
        let selection = selection(currentSelected: currentSelected)
        guard let itemId = selection.first, let model = itemController.modelSync(for: itemId) else { return [] }
        let folders = itemController.collections(isFolder: false, in: model.parentId)
        return folders.map { FolderRepresentable(id: $0.id, name: $0.name) }
    }
    
    func addItem(currentSelected: UUID?, to folder: FolderRepresentable) {
        let selection = selection(currentSelected: currentSelected)
        guard let collection = itemController.modelSync(for: folder.id) else { return }
        for itemId in selection {
            guard let model = itemController.modelSync(for: itemId) else { continue }
            editController.addItem(itemId: model.id, in: collection, folderId: nil)
        }
    }
}
