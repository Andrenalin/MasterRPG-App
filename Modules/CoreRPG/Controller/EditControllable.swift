// @copyright André Trettin

import Foundation
import SwiftData
import SwiftUI

public protocol EditControllable: Sendable {
    associatedtype Model: ItemDataAccessable, ItemDataModelable, ListItemFolderable, PersistentModel

    var fileUrlDataController: FileUrlDataController? { get }

    func createNewEntry(in model: Model, childId: UUID) -> Model.Entry
    func duplicate(model: Model)
}

// MARK: - Edit Item
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
            await fileUrlDataController?.delete(fileUrl)
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
}

// MARK: - Folder / Collection
public extension EditControllable {
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
                //item.parentId = folderId
            }
        }
    }

    func removeItem(offsets: IndexSet, model: Model) {
        model.withTransaction { modelContext in
            let removedEntries = model.entryModels.filter { offsets.contains($0.index) }
            var entries: [Model.Entry] = model.entryModels
            entries.remove(atOffsets: offsets)
            reindex(entries: &entries)
            model.reset(entries: entries)

            if model.category == .folder {
                removedEntries.forEach {
                    if let entryModel = $0 as? (any PersistentModel) {
                        modelContext.delete(entryModel)
                    }
                    if let entry = Model.model(modelContext: modelContext, id: $0.childId) {
                        entry.reset(displayState: 2)
                    }
                }
            }
        }
    }

    func moveItems(source: IndexSet, destination: Int, model: Model) {
        model.withTransaction { modelContext in
            var entries = model.entryModels
            entries.move(fromOffsets: source, toOffset: destination)
            entries = entries.enumerated().map { index, entry in
                var updatedEntry = entry
                updatedEntry.index = index
                return updatedEntry
            }
            model.reset(entries: entries)
        }
    }
}

// MARK: - Group Items
public extension EditControllable {
    func addGroup(childId: UUID, model: Model) {
        model.withTransaction { modelContext in
            var entries: [Model.Entry] = model.entryModels

            let entry = createNewEntry(in: model, childId: childId)
            entries.append(entry)
            model.reset(entries: entries)
            if let entry = entry as? (any PersistentModel) {
                modelContext.insert(entry)
            }
            guard let subModel = Model.model(modelContext: modelContext, id: childId) else { return }
            subModel.reset(displayState: 1)
        }
    }

    func removeGroup(childId: UUID, model: Model) {
        model.withTransaction { modelContext in
            var entries: [Model.Entry] = model.entryModels
            let entry = model[childId]
            entries.removeAll(where: { $0.childId == childId })
            reindex(entries: &entries)
            model.reset(entries: entries)

            guard let subModel = Model.model(modelContext: modelContext, id: childId) else { return }
            if let entry = entry as? (any PersistentModel) {
                modelContext.delete(entry)
            }
            subModel.reset(displayState: 0)
        }
    }
}

// MARK: - Editor
public extension EditControllable {
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

    private func reindex(entries: inout [Model.Entry]) {
        entries = entries.enumerated().map { index, entry in
            var updatedEntry = entry
            updatedEntry.index = index
            return updatedEntry
        }
    }
}

public extension EditControllable {
    func resetFile(url: URL?, in model: Model) {}
}
