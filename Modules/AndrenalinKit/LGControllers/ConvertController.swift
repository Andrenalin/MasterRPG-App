// @copyright André Trettin

import Foundation

public struct ConvertController {
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
}
