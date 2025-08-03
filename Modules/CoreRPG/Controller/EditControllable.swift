// @copyright André Trettin

import Foundation
import SwiftData

public protocol EditControllable: Sendable {
    associatedtype Model: ItemDataAccessable, ItemDataModelable, ListItemFolderable, PersistentModel

    var fileUrlDataController: FileUrlDataController { get }
    
    @MainActor func addNew(modelContext: ModelContext, type: EditControllerAddType) -> Model
    func delete(model: Model)
    
    func addItem(itemId: UUID, in modelContext: ModelContext, parentId: UUID?, folderId: UUID?)

    func update(model: Model, name: String, information: String, category: ItemListCategory, tags: [String])
    func resetFile(url: URL?, in model: Model)
}


public extension EditControllable {
    @MainActor func addNew(modelContext: ModelContext, type: EditControllerAddType) -> Model {
        let newItem = Model.newItem
        modelContext.insert(newItem)
        if type == .folder {
            newItem.reset(category: .folder)
        } else if type == .collection {
            newItem.reset(category: Model.collectionCategory)
        }
        try? modelContext.save()
        return newItem
    }
    
    func delete(model: Model) {
        let fileUrl = model.fileUrl
        let modelContext = model.modelContext
        Task.detached {
            await fileUrlDataController.delete(fileUrl)
        }
        model.entryModels.forEach { entry in
            if var entryItem = Model.model(modelContext: modelContext, id: entry.childId) {
                if model.category == .folder {
                    entryItem.parentId = model.parentId
                }
                entryItem.reset(displayState: 0)
            }
        }
        model.reset(displayState: 2)
        //updateTags(modelContext: modelContext)
        try? modelContext?.save()
    }

}
