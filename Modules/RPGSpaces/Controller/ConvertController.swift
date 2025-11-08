// @copyright André Trettin

import AndrenalinKit
import Foundation

struct ConvertController {
    let itemController: ItemController
    let editController: EditController
    
    @MainActor func checkFolders() {
        for itemId in itemController.itemDataModel.items {
            guard let model = itemController.itemSync(for: itemId), model.specialCategory == false, let url = model.fileUrl?.rawUrl else { continue }
            
            // Extract folder path components from the file URL
            var currentParentId: UUID? = nil
            var currentFolderModel: SpaceModel? = nil
            let folderComponents = url.pathComponents.dropLast() // drop root '/' and the file name
            for folderName in folderComponents {
                guard folderName != "/" else { continue }
                // Find folder at this level with the same name and parent
                var folderId = itemController.itemDataModel.items.first {
                    let item = itemController.itemOrEmpty(for: $0)
                    return item.category == .folder && item.name == folderName && item.parentId == currentParentId
                }
                
                if folderId == nil {
                    // If not found, create
                    let newModel = SpaceModel(id: UUID(), name: folderName, description: "", tags: [], category: .folder, displayState: 0, degrees: 0, fileUrl: nil, entries: [], parentId: nil)
                    itemController.replace(model: newModel, isInsert: true, shouldRepairLinks: false)
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
