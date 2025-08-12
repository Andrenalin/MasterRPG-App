// @copyright André Trettin

import AndrenalinKit
import CoreRPG
import Foundation
import RPGPhotos
import SwiftData

public struct ConverterController {
    public static func insert(items: [RPGPhotos.PhotoModel], into modelContext: ModelContext, root: PhotoRootModel) {
        let fetchDesc = FetchDescriptor<PhotoDataModel>()
        var models = (try? modelContext.fetch(fetchDesc)) ?? []

        var addedGroups: [UUID: [UUID]] = [:]
        
        items.forEach { item in
            guard !models.contains(where: { $0.id == item.id }) else { return }

            // Insert the photo model first with an empty entries array
            let photoModel = PhotoDataModel(
                id: item.id,
                name: item.name,
                information: item.description,
                category: CoreRPG.ItemListCategory(rawValue: item.category.rawValue) ?? .adventure,
                tags: item.tags,
                displayState: item.displayState,
                url: item.fileUrl?.rawUrl,
                entries: [],
                degrees: item.degrees
            )
            modelContext.insert(photoModel)
            var currentParentId: UUID? = nil
            var currentFolderModel: PhotoDataModel? = nil
            // Extract folder path components from the file URL
            if let url = item.fileUrl?.rawUrl {
                let folderComponents = url.pathComponents.dropFirst().dropLast() // drop root '/' and the file name
                for folderName in folderComponents {
                    // Find folder at this level with the same name and parent
                    let folderModel = models.first(where: { $0.category == .folder && $0.name == folderName && $0.parentId == currentParentId }) ??
                        {
                            // If not found, create
                            let newFolder = PhotoDataModel(
                                name: folderName,
                                information: "",
                                category: .folder,
                                parentId: currentParentId
                            )
                            modelContext.insert(newFolder)
                            models.append(newFolder)
                            if let currentFolderModel {
                                root.editController.addItem(itemId: newFolder.id, in: currentFolderModel, folderId: currentParentId)
                            }
                            return newFolder
                        }()
                    currentParentId = folderModel.id
                    currentFolderModel = folderModel
                }
            }
            // If we found/created folders, add the photo to the deepest one
            if let folderModel = currentFolderModel {
                root.editController.addItem(itemId: item.id, in: folderModel, folderId: folderModel.id)
            }
            
            let entries = item.entries.enumerated().map { (index, entry) in
                entry.photoId
            }
            addedGroups[item.id] = entries
        }
        
        addedGroups.forEach { (id, entries) in
            guard let model = PhotoDataModel.model(modelContext: modelContext, id: id) else { return }
            entries.forEach {
                root.editController.addGroup(childId: $0, model: model)
            }
        }
        
        
    }
}

