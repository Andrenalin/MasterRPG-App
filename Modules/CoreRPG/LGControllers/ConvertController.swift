// @copyright André Trettin

import Foundation

public struct ConvertController: Sendable {
    public init(itemController: any ItemControllable, editController: any EditControllable) {
        self.itemController = itemController
        self.editController = editController
    }
    
    let itemController: any ItemControllable
    let editController: any EditControllable
    
    @MainActor public func checkFolders() async {
        for itemId in itemController.itemDataModel.items {
            guard let model = itemController.itemSync(for: itemId), model.specialCategory == false, let url = model.fileUrl?.rawUrl else { continue }
            
            // Extract folder path components from the file URL
            var currentParentId: UUID? = nil
            var currentFolderModel: (any ItemDataAccessable)? = nil
            let folderComponents = url.pathComponents.dropLast() // drop root '/' and the file name
            for folderName in folderComponents {
                guard folderName != "/" else { continue }
                // Find folder at this level with the same name and parent
                var folderId = itemController.itemDataModel.items.first {
                    let item = itemController.itemOrEmpty(for: $0)
                    return item.category == .folder && item.name == folderName && item.parentId == currentParentId
                }
                
                if folderId == nil, var newModel = await editController.addNew(type: .folder) {
                    // If not found, create
                    newModel.name = folderName
                    editController.addItem(itemId: newModel.id, parentId: currentParentId)
                    folderId = newModel.id
                }
                
                if let folderId {
                    currentParentId = folderId
                    currentFolderModel = itemController.itemOrEmpty(for: folderId)
                }
            }
            
            // If we found/created folders, add the photo to the deepest one
            if let folderModel = currentFolderModel {
                editController.addItem(itemId: model.id, parentId: folderModel.id)
            }
        }
    }
    
    @MainActor public func createFolderAndCollections() async {
        for itemId in itemController.itemDataModel.items {
            guard let model = itemController.itemSync(for: itemId), model.specialCategory == false, model.category != .item else { continue }
            
            // Extract folder from category
            let folderName = model.category.title
            
            var folderId = itemController.itemDataModel.items.first {
                let item = itemController.itemOrEmpty(for: $0)
                return item.category == .folder && item.name == folderName && item.parentId == nil
            }
            
            if folderId == nil, var newModel = await editController.addNew(type: .folder) {
                // If not found, create
                newModel.name = folderName
                folderId = newModel.id
            }
            
            if let folderId {
                let currentFolderModel = itemController.itemOrEmpty(for: folderId)
                editController.setCurrentItem(to: ItemRowTreeModel(itemId: model.id, typeId: itemController.itemDataModel.networkModule))
                let category = model.category
                editController.reset(category: .item, saveIt: false)
                editController.reset(tags: [category.title] + model.tags)
                editController.addItem(itemId: model.id, parentId: currentFolderModel.id)
            }
        }

        let count = itemController.itemDataModel.items.count
        guard count > 50 else { return }
        
        for tag in itemController.itemDataModel.allTags {
            let tagItems = itemController.itemDataModel.items.filter {
                let item = itemController.itemOrEmpty(for: $0)
                return item.tags.contains(tag)
            }
            guard tagItems.count >= count / 10 else { continue }
           
            // Collections
            let tabName = tag.localizedLowercase.localizedCapitalized
                
            var collectionId = itemController.itemDataModel.items.first {
                let item = itemController.itemOrEmpty(for: $0)
                return item.specialCategory && item.category != .folder && item.name == tabName && item.parentId == nil
            }

            if collectionId == nil, var newModel = await editController.addNew(type: .collection) {
                // If not found, create
                newModel.name = tabName
                collectionId = newModel.id
            }

            if let collectionId, let currentCollectionModel = itemController.itemSync(for: collectionId) {
                for tagItem in tagItems {
                    editController.addItem(itemId: tagItem.id, parentId: currentCollectionModel.id)
                }
            }
        }
    }
}
