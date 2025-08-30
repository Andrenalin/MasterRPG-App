// @copyright André Trettin

import Foundation
import SwiftData
import SwiftUI

public protocol EditControllable: Sendable {
    var itemControllable: ItemControllable { get }
    var fileUrlDataController: FileUrlDataController? { get }

}

// MARK: - Edit Item
public extension EditControllable {
    func createNewEntry(in model: ItemDataModel, childId: UUID) -> EntryDataModel {
        EntryDataModel(id: UUID(), index: model.entries.count, parentId: model.id, childId: childId, item: model)
    }

    func duplicate(model: ItemDataModel) {
        let newId = UUID()
        guard let actor = model.modelActor() else { return }
        let id = model.id
        Task.detached {
            await actor.setup(id: id)
            let fileUrl = try? await fileUrlDataController?.duplicate(fileUrl: actor.fileUrl, for: newId)
            await actor.duplicate(newId: newId, url: fileUrl?.rawUrl)
            await actor.save()
        }
    }

    func addNew(modelContext: ModelContext, module: NetworkModules, type: EditControllerAddType) -> ItemDataModel {
        let newItem = ItemDataModel.newItem
        newItem.module = module
        modelContext.insert(newItem)
        if type == .folder {
            newItem.reset(category: .folder)
        } else if type == .collection {
            newItem.reset(category: itemControllable.collectionCategory)
        }
        try? modelContext.save()
        return newItem
    }

    func delete(model: ItemDataModel) {
        let fileUrl = model.fileUrl
        let modelContext = model.modelContext
        Task.detached {
            await fileUrlDataController?.delete(fileUrl)
        }
        model.entries.forEach { entry in
            if let entryItem = ItemDataModel.model(modelContext: modelContext, id: entry.childId) {
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
        guard let model = ItemDataModel.model(modelContext: modelContext, id: parentId) else { return }
        addItem(itemId: itemId, in: model, folderId: folderId)
    }

    func addItem(itemId: UUID, in model: ItemDataModel, folderId: UUID?) {
        guard itemId != model.id else { return }
        model.withTransaction { modelContext in
            guard let item = ItemDataModel.model(modelContext: modelContext, id: itemId) else { return }
            if item.specialCategory && !model.isFolder {
                return
            }
            var entries: [EntryDataModel] = model.entries
            let entry = createNewEntry(in: model, childId: itemId)
            entries.append(entry)
            model.reset(entries: entries)
            modelContext.insert(entry)

            if model.category == .folder {
                item.parentId = model.id
            } else {
                //item.parentId = folderId
            }
        }
    }

    func removeItem(offsets: IndexSet, model: ItemDataModel) {
        model.withTransaction { modelContext in
            let removedEntries = model.entries.filter { offsets.contains($0.index) }
            var entries: [EntryDataModel] = model.entries
            entries.remove(atOffsets: offsets)
            reindex(entries: &entries)
            model.reset(entries: entries)

            if model.category == .folder {
                removedEntries.forEach {
                    modelContext.delete($0)
                    if let entry = ItemDataModel.model(modelContext: modelContext, id: $0.childId) {
                        entry.reset(displayState: 2)
                    }
                }
            }
        }
    }

    func moveItems(source: IndexSet, destination: Int, model: ItemDataModel) {
        model.withTransaction { modelContext in
            var entries = model.entries
            entries.move(fromOffsets: source, toOffset: destination)
            entries = entries.enumerated().map { index, entry in
                let updatedEntry = entry
                updatedEntry.index = index
                return updatedEntry
            }
            model.reset(entries: entries)
        }
    }
}

// MARK: - Group Items
public extension EditControllable {
    func addGroup(childId: UUID, model: ItemDataModel) {
        guard model.id != childId else { return }
        model.withTransaction { modelContext in
            var entries: [EntryDataModel] = model.entries

            let entry = createNewEntry(in: model, childId: childId)
            entries.append(entry)
            model.reset(entries: entries)
            modelContext.insert(entry)

            guard let subModel = ItemDataModel.model(modelContext: modelContext, id: childId) else { return }
            subModel.reset(displayState: 1)
        }
    }

    func removeGroup(childId: UUID, model: ItemDataModel) {
        guard model.id != childId else { return }
        model.withTransaction { modelContext in
            var entries: [EntryDataModel] = model.entries
            let entry = model[childId]
            entries.removeAll(where: { $0.childId == childId })
            reindex(entries: &entries)
            model.reset(entries: entries)

            guard let subModel = ItemDataModel.model(modelContext: modelContext, id: childId) else { return }
            modelContext.delete(entry)
            subModel.reset(displayState: 0)
        }
    }
}

// MARK: - Editor
public extension EditControllable {
    func update(model: ItemDataModel, name: String, information: String, category: ItemListCategory, tags: [String]) {
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
        let fetch = FetchDescriptor<ItemDataModel>()
        guard let models = try? modelContext.fetch(fetch), let module = models.first?.module else { return }
        let tags = Set(models.flatMap { $0.tags })
        TagController.update(tags: tags, in: module, modelContext: modelContext)
    }

    private func reindex(entries: inout [EntryDataModel]) {
        entries = entries.enumerated().map { index, entry in
            let updatedEntry = entry
            updatedEntry.index = index
            return updatedEntry
        }
    }
}

public extension EditControllable {
    func resetFile(url: URL?, in model: ItemDataModel) {
        guard let actor = model.modelActor() else { return }
        let id = model.id
        Task.detached {
            await actor.setup(id: id)
            await resetFile(url: url, id: id, actor: actor)
            await actor.save()
        }
    }
    
    private func resetFile(url: URL?, id: UUID, actor: DataModelActor) async {
        guard let fileUrlDataController else { return }
        await fileUrlDataController.delete(await actor.fileUrl)
        guard let url else {
            await actor.update(url: url)
            return
        }
        _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }
        
        if await actor.name.isEmpty {
            let ext = url.pathExtension.isEmpty ? "" : ".\(url.pathExtension)"
            let name = url.lastPathComponent.replacingOccurrences(of: ext, with: "")
            await actor.update(name: name)
        }
        let updatedFileUrl = try? await fileUrlDataController.createFileUrl(fileId: id, url: url, module: actor.module.token, category: actor.category.title)
        await actor.update(url: updatedFileUrl?.rawUrl)
    }
}
