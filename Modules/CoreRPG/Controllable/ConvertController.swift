// @copyright André Trettin

import Foundation

public struct ConvertController: Sendable {
    public init(itemController: any ItemControllable, editController: any EditControllable) {
        self.itemController = itemController
        self.editController = editController
    }
    
    let itemController: any ItemControllable
    let editController: any EditControllable
    
    @MainActor public func repairHiddenAndFolders(reportModel: ValidateRepairModel, importedIds: Set<UUID> = []) async {
        for itemId in itemController.itemDataModel.items {
            guard importedIds.isEmpty || importedIds.contains(itemId) else { continue }
            guard let item = itemController.itemSync(for: itemId) else { continue }

            // Increment progress and yield so @Observable notifies SwiftUI before continuing.
            // Without the yield every update queues up and SwiftUI renders them all at once at the end.
            reportModel.increaseCurrent()
            await Task.yield()

            if item.isFolder {
                editController.cleanFolder(itemId: itemId)
            }

            let repairFolder = itemController.config.module != .value
            if repairFolder, let parentId = item.parentId {
                if let parent = itemController.itemSync(for: parentId) {
                    let isOrphaned = !parent.entries.contains(where: { $0.childId == item.id })
                    if isOrphaned {
                        editController.removeItemFromParent(itemId: item.id, oneUp: false, moveFiles: false)
                    }
                } else {
                    editController.removeItemFromParent(itemId: item.id, oneUp: false, moveFiles: false)
                }
            }

            if editController.isOrphanedHidden(itemId: itemId) {
                editController.willRepairOrphan(itemId: itemId)
                editController.reset(hidden: false, itemId: itemId)
            }

            if !item.specialCategory && item.category != .entry {
                let category = item.category
                editController.reset(category: .entry, itemId: itemId)
                editController.reset(tags: [category.title] + item.tags, itemId: itemId)
            }

            if itemController.config.module == .photo && item.category == .entry {
                for entry in item.entries {
                    editController.removeGroup(itemId: itemId, childId: entry.childId)
                }
            }

            if let url = item.url {
                await extractFolderAndCreate(url: url, item: item)
            }
        }
    }
    
    @MainActor public func moveAndCreateFolders(itemId: UUID) async {
        guard let item = itemController.itemSync(for: itemId), let url = item.url else { return }
        await extractFolderAndCreate(url: url, item: item)
    }
    
    @MainActor public func extractFolderAndCreate(url: URL, item: any ItemDataAccessable) async {
        var currentParentId: UUID? = nil
        var currentFolderModel: (any ItemDataAccessable)? = nil
        let folderComponents = url.pathComponents.dropLast() // drop root '/' and the file name
        for folderName in folderComponents {
            guard folderName != "/" else { continue }
            // Find folder at this level with the same name and parent
            var folderId = itemController.itemDataModel.items.first {
                let folderItem = itemController.itemOrEmpty(for: $0)
                return folderItem.category == .folder && folderItem.name == folderName && folderItem.parentId == currentParentId
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
        
        // If we found/created folders, add the item to the deepest one — skip if already there
        if let folderModel = currentFolderModel, item.parentId != folderModel.id {
            editController.addItem(itemId: item.id, parentId: folderModel.id)
            editController.checkChildrenExists(itemId: folderModel.id)
        }
    }
    

    @MainActor public func createFilepathFoldersAndCollections(reportModel: ValidateRepairModel) async {
        var tagCounter: [String: [UUID]] = [:]
        
        reportModel.currentSection = "Create Folders"
        for itemId in itemController.itemDataModel.items {
            reportModel.increaseCurrent()
            guard let model = itemController.itemSync(for: itemId) else { continue }

            if model.parentId == nil && model.displayState == 0 {
                for tag in model.tags {
                    tagCounter[tag, default: []] += [model.id]
                }
                tagCounter[model.category.title, default: []] += [model.id]
            }

            guard model.specialCategory == false, model.category != .entry else { continue }
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
        
        reportModel.currentSection = "Create Tags"
        await createTags(tagCounter: tagCounter)
        reportModel.currentSection = "Create Collections"
        await createCollections(tagCounter: tagCounter)
    }
    
    @MainActor public func createFoldersAndCollections(reportModel: ValidateRepairModel, excludeHidden: Bool = false, overwriteEntryCheck: Bool = false) async {
        var tagCounter: [String: [UUID]] = [:]
        var categoryCounter: [ItemListCategory: [UUID]] = [:]
        
        reportModel.currentSection = "Processing Items"
        
        for itemId in itemController.itemDataModel.items {
            reportModel.increaseCurrent()
            
            guard let model = itemController.itemSync(for: itemId) else { continue }
            guard !excludeHidden || model.displayState == 0 else { continue }

            for tag in model.tags {
                tagCounter[tag, default: []] += [model.id]
            }
            
            let linkModels = model.linkRegisterModels
            editController.linkRegisterController.register(links: linkModels)

            guard model.specialCategory == false, (overwriteEntryCheck || model.category != .entry) else { continue }
            guard model.parentId == nil else { continue }
            
            categoryCounter[model.category, default: []] += [model.id]
            
            let addedTags = model.category.title
            editController.reset(category: .entry, itemId: model.id)
            editController.reset(tags: [addedTags] + model.tags, itemId: model.id)
            if model.parentId == nil && model.displayState != 0 {
                editController.reset(hidden: false, itemId: model.id)
            }
        }
        
        reportModel.currentSection = "Create Tags"
        await createTags(tagCounter: tagCounter)
        reportModel.currentSection = "Create Folders"
        await createFolders(categoryConunter: categoryCounter)
        reportModel.currentSection = "Create Collection"
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
        
    @MainActor func createTags(tagCounter: [String: [UUID]]) async {
        for (key, values) in tagCounter {
            editController.tagController.reset(tag: key, count: values.count, module: itemController.config.module)
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
