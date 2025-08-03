// @copyright André Trettin

import Foundation
import SwiftData

public protocol EditControllable: Sendable {
    associatedtype Model: ItemDataAccessable, ItemDataModelable, ListItemFolderable, PersistentModel

    var fileUrlDataController: FileUrlDataController { get }

    func createNewEntry(in model: Model, childId: UUID) -> Model.Entry
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
        updateTags(modelContext: modelContext)
        try? modelContext?.save()
    }

    func addItem(itemId: UUID, in modelContext: ModelContext, parentId: UUID?, folderId: UUID?) {
        guard let model = Model.model(modelContext: modelContext, id: parentId) else { return }
        addItem(itemId: itemId, in: model, folderId: folderId)
    }

    func addItem(itemId: UUID, in model: Model, folderId: UUID?) {
        guard itemId != model.id else { return }
        model.withTransaction { modelContext in
            guard var item = Model.model(modelContext: modelContext, id: itemId) else { return }
            var entries: [Model.Entry] = model.entryModels
            let entry = createNewEntry(in: model, childId: itemId)
            entries.append(entry)
            model.reset(entries: entries)
            if let entry = entry as? (any PersistentModel) {
                modelContext.insert(entry)
            }
            if model.category == .folder {
                item.parentId = model.id
            } else {
                item.parentId = folderId
            }
        }
    }

    func removeItem(itemId: UUID, model: Model) {
        model.withTransaction { modelContext in
            guard var item = Model.model(modelContext: modelContext, id: itemId) else { return }
            
            let entry = model[itemId]
            var entries: [Model.Entry] = model.entryModels
            entries.removeAll(where: { $0.childId == itemId })
            entries = entries.enumerated().map { index, entry in
                var updatedEntry = entry
                updatedEntry.index = index
                return updatedEntry
            }
            if let entry = entry as? (any PersistentModel) {
                modelContext.delete(entry)
            }
            if model.category == .folder {
                item.parentId = nil
            }
            item.reset(displayState: 0)
        }
    }

    func update(model: Model, name: String, information: String, category: ItemListCategory, tags: [String]) {
        model.withTransaction { modelContext in
            model.reset(name: name)
            model.reset(information: information)
            model.reset(category: category)
            model.reset(tags: tags)
        }
        updateTags(modelContext: model.modelContext)
    }

    func updateTags(modelContext: ModelContext?) {
        guard let modelContext else { return }
        let fetch = FetchDescriptor<Model>()
        guard let models = try? modelContext.fetch(fetch) else { return }
        let tags = Set(models.flatMap { $0.tags })
        TagController.update(tags: tags, in: Model.typeId, modelContext: modelContext)
    }
}
