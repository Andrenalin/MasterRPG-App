// @copyright André Trettin

import Foundation
import SwiftData
import SwiftUI

public protocol ConverterControllable: Sendable {
}

public extension ConverterControllable {
    static func convert(category: ItemListCategory, tags: [String], module: NetworkModules, collection: ItemListCategory) -> (ItemListCategory, [String]) {
        if category == .folder || category == collection {
            return (category, tags)
        }
        return (.item, [category.title] + tags)
    }

    @MainActor
    static func convert(editControllable: any EditControllable, item: ItemDataModel, items: [ItemDataModel], modelContext: ModelContext) {
        var allItems = items
        for item in items {
            guard let url = item.url else { return }

            var currentParentId: UUID? = nil
            var currentFolderModel: ItemDataModel? = nil
            // Extract folder path components from the file URL
            let folderComponents = url.pathComponents.dropFirst().dropLast() // drop root '/' and the file name
            for folderName in folderComponents {
                // Find folder at this level with the same name and parent
                var folderModel: ItemDataModel
                if let foundModel = allItems.first(where: { $0.category == .folder && $0.name == folderName && $0.parentId == currentParentId }) {
                    folderModel = foundModel
                } else {
                    // If not found, create
                    let newFolder = ItemDataModel(
                        module: item.module,
                        name: folderName,
                        information: "",
                        category: .folder,
                        parentId: currentParentId
                    )
                    modelContext.insert(newFolder)
                    allItems.append(newFolder)
                    if let currentFolderModel {
                        editControllable.addItem(itemId: newFolder.id, in: currentFolderModel, folderId: currentParentId)
                    }
                    folderModel = newFolder
                }
                currentParentId = folderModel.id
                currentFolderModel = folderModel
            }
            // If we found/created folders, add the photo to the deepest one
            if let folderModel = currentFolderModel {
                editControllable.addItem(itemId: item.id, in: folderModel, folderId: folderModel.id)
            }
        }
    }
}
