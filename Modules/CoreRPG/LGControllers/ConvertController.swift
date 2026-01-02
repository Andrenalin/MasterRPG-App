// @copyright André Trettin

import Foundation

public struct ConvertController: Sendable {
    public init(itemController: any ItemControllable, editController: any EditControllable) {
        self.itemController = itemController
        self.editController = editController
    }
    
    let itemController: any ItemControllable
    let editController: any EditControllable
    
    @MainActor public func createFilepathFoldersAndCollections() async {
        var tagCounter: [String: [UUID]] = [:]
        
        for itemId in itemController.itemDataModel.items {
            guard let model = itemController.itemSync(for: itemId), model.specialCategory == false, model.category != .entry else { continue }

            if model.parentId == nil && model.displayState == 0 {
                for tag in model.tags {
                    tagCounter[tag, default: []] += [model.id]
                }
                tagCounter[model.category.title, default: []] += [model.id]
            }
            
            guard model.displayState == 0 else { continue }
            guard let url = model.fileUrl?.rawUrl else { continue }
            
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
                
                if folderId == nil, let newModel = await editController.addNew(type: .folder) {
                    // If not found, create
                    editController.reset(name: folderName, itemId: newModel.id)
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
                let category = model.category
                editController.reset(category: .entry, itemId: model.id)
                editController.reset(tags: [category.title] + model.tags, itemId: model.id)
                editController.addItem(itemId: model.id, parentId: folderModel.id)
            }
        }
        
        await createCollections(tagCounter: tagCounter)
    }
    
    @MainActor public func createFoldersAndCollections(excludeHidden: Bool = false) async {
        var tagCounter: [String: [UUID]] = [:]
        var categoryCounter: [ItemListCategory: [UUID]] = [:]
        
        for itemId in itemController.itemDataModel.items {
            guard let model = itemController.itemSync(for: itemId), model.specialCategory == false, model.category != .entry else { continue }
            guard model.parentId == nil else { continue }
            guard !excludeHidden || model.displayState == 0 else { continue }
            
            for tag in model.tags {
                tagCounter[tag, default: []] += [model.id]
            }

            categoryCounter[model.category, default: []] += [model.id]
            
            let addedTags = model.category.title
            editController.reset(category: .entry, itemId: model.id)
            editController.reset(tags: [addedTags] + model.tags, itemId: model.id)
            if model.parentId == nil && model.displayState != 0 {
                editController.reset(hidden: false, itemId: model.id)
            }
        }
        
        await createFolders(categoryConunter: categoryCounter)
        await createCollections(tagCounter: tagCounter)
    }
    
    @MainActor func createFolders(categoryConunter: [ItemListCategory: [UUID]]) async {
        for category in categoryConunter.keys {
            let models = categoryConunter[category, default: []]
            guard !models.isEmpty else { continue }

            // Extract folder from category
            let folderName = category.title
            
            var folderId = itemController.itemDataModel.items.first {
                let item = itemController.itemOrEmpty(for: $0)
                return item.category == .folder && item.name == folderName && item.parentId == nil
            }
            
            if folderId == nil, let newModel = await editController.addNew(type: .folder) {
                // If not found, create
                editController.reset(name: folderName, itemId: newModel.id)
                folderId = newModel.id
            }
            
            if let folderId {
                if let currentFolderModel = itemController.itemSync(for: folderId) {
                    for itemId in models {
                        editController.addItem(itemId: itemId, parentId: currentFolderModel.id)
                    }
                }
            }
        }
    }
    
    @MainActor func createCollections(tagCounter: [String: [UUID]]) async {
        let count = itemController.itemDataModel.items.count
        guard count > 50 else { return }

        let tags: [String] = tagCounter.compactMap { (key, value) in
            value.count >= count / 10 ? key : nil
        }
        
        for tag in tags {
            // Collections
            let tabName = tag.localizedLowercase.localizedCapitalized
                
            var collectionId = itemController.itemDataModel.items.first {
                let item = itemController.itemOrEmpty(for: $0)
                return item.specialCategory && item.category != .folder && item.name == tabName && item.parentId == nil
            }
                
            if collectionId == nil, let newModel = await editController.addNew(type: .collection) {
                    // If not found, create
                editController.reset(name: tabName, itemId: newModel.id)
                collectionId = newModel.id
            }

            if let collectionId, let currentCollectionModel = itemController.itemSync(for: collectionId) {
                for itemId in tagCounter[tag, default: []] {
                    editController.addItem(itemId: itemId, parentId: currentCollectionModel.id)
                }
            }
        }
    }
}
