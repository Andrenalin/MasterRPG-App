// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData
import UniformTypeIdentifiers

#if os(macOS)
internal import AppKit
#else
internal import UIKit
#endif

struct EditController {
    let fileUrlDataController: FileUrlDataController
}

extension EditController: EditControllable {
    typealias Model = SpaceDataModel
}

// MARK: - Edit Data Model Properties
extension EditController {
    @MainActor func addNew(modelContext: ModelContext, type: EditControllerAddType) -> SpaceDataModel {
        let newItem = SpaceDataModel.newItem
        if type == .folder {
            newItem.category = .folder
        } else if type == .collection {
            newItem.category = SpaceDataModel.collectionCategory
        }
        modelContext.insert(newItem)
        try? modelContext.save()
        return newItem
    }
    
    func duplicate(model: SpaceDataModel) {
        let newId = UUID()
        guard let actor = model.modelActor() else { return }
        let id = model.id
        Task.detached {
            await actor.setup(id: id)
            let fileUrl = try? await fileUrlDataController.duplicate(fileUrl: actor.fileUrl, for: newId)
            await actor.duplicate(url: fileUrl?.rawUrl)
            await actor.save()
        }
    }
    
    func delete(model: SpaceDataModel) {
        let fileUrl = model.fileUrl
        let modelContext = model.modelContext
        Task.detached {
            await fileUrlDataController.delete(fileUrl)
        }
        model.entryModels.forEach { entry in
            if let entryItem = SpaceDataModel.model(modelContext: modelContext, id: entry.childId) {
                if model.category == .folder {
                    entryItem.parentId = model.parentId
                }
                entryItem.displayState = 0
            }
        }
        model.displayState = 2
        updateTags(modelContext: modelContext)
        try? modelContext?.save()
    }
    
    func addItem(itemId: UUID, in modelContext: ModelContext, parentId: UUID?, folderId: UUID?) {
        guard let model = SpaceDataModel.model(modelContext: modelContext, id: parentId) else { return }
        addItem(itemId: itemId, in: model, folderId: folderId)
    }

    func addItem(itemId: UUID, in model: SpaceDataModel, folderId: UUID?) {
        guard itemId != model.id else { return }
        model.withTransaction { modelContext in
            guard let item = SpaceDataModel.model(modelContext: modelContext, id: itemId) else { return }
            
            var entries: [SpaceEntryDataModel] = model.entryModels
            let entry = SpaceEntryDataModel(id: UUID(), index: Int16(entries.count), parentId: model.id, childId: itemId, item: model)
            entries.append(entry)
            model.entryModels = entries
            modelContext.insert(entry)
            if model.category == .folder {
                item.parentId = model.id
            } else {
                item.parentId = folderId
            }
        }
    }

    func removeItem(itemId: UUID, model: SpaceDataModel) {
        model.withTransaction { modelContext in
            guard let item = SpaceDataModel.model(modelContext: modelContext, id: itemId) else { return }
            
            let entry = model[itemId]
            model.entryModels.removeAll(where: { $0.childId == itemId })
            model.entryModels.enumerated().forEach { index, entry in
                entry.index = Int16(index)
            }
            modelContext.delete(entry)
            if model.category == .folder {
                item.parentId = nil
            }
            item.displayState = 0
        }
    }


    func addSubPhoto(photoId: UUID, model: SpaceDataModel) {
        model.withTransaction { modelContext in
            var entries: [SpaceEntryDataModel] = model.entryModels
            
            let entry = SpaceEntryDataModel(id: UUID(), index: Int16(entries.count), parentId: model.id, childId: photoId, item: model)
            entries.append(entry)
            model.entryModels = entries
            
            guard let subModel = SpaceDataModel.model(modelContext: modelContext, id: photoId) else { return }
            modelContext.insert(entry)
            subModel.displayState = DisplayStateMask.totalHidden.rawValue
        }
    }
    
    func removeSubPhoto(photoId: UUID, model: SpaceDataModel) {
        model.withTransaction { modelContext in
            let entry = model[photoId]
            model.entryModels.removeAll(where: { $0.childId == photoId })
            model.entryModels.enumerated().forEach { index, entry in
                entry.index = Int16(index)
            }
            
            guard let subModel = SpaceDataModel.model(modelContext: modelContext, id: photoId) else { return }
            modelContext.delete(entry)
            subModel.displayState = 0
        }
    }
    
    func update(model: SpaceDataModel, name: String, information: String, category: ItemListCategory, tags: [String]) {
        model.withTransaction { modelContext in
            model.reset(name: name)
            model.reset(information: information)
            model.category = category
            model.tags = tags
        }
        updateTags(modelContext: model.modelContext)
    }
    
    func updateTags(modelContext: ModelContext?) {
        guard let modelContext else { return }
        let fetch = FetchDescriptor<SpaceDataModel>()
        guard let models = try? modelContext.fetch(fetch) else { return }
        let tags = Set(models.flatMap { $0.tags })
        TagController.update(tags: tags, in: SpaceDataModel.typeId, modelContext: modelContext)
    }
}

// MARK: - File editor
extension EditController {
    func resetFile(url: URL?, in model: SpaceDataModel) {
        guard let actor = model.modelActor() else { return }
        let id = model.id
        Task.detached {
            await actor.setup(id: id)
            await resetFile(url: url, id: id, actor: actor)
            await actor.save()
        }
    }

    private func resetFile(url: URL?, id: UUID, actor: DataModelActor) async {
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
        let updatedFileUrl = try? await fileUrlDataController.createFileUrl(fileId: id, url: url, module: SpaceDataModel.typeId.token, category: actor.category.title)
        await actor.update(url: updatedFileUrl?.rawUrl)
    }
}
