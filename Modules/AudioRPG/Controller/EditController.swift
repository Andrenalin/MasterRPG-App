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
    let fileController: FileController
}

extension EditController: EditControllable {
    typealias Model = AudioDataModel
}

// MARK: - Edit Data Model Properties
extension EditController {
    @MainActor func addNew(modelContext: ModelContext, type: EditControllerAddType) -> AudioDataModel {
        let newItem = AudioDataModel.newItem
        modelContext.insert(newItem)
        if type == .folder {
            newItem.category = .folder
        } else if type == .collection {
            newItem.category = AudioDataModel.collectionCategory
        }
        try? modelContext.save()
        return newItem
    }
    
    func duplicate(model: AudioDataModel) {
        let newId = UUID()
        guard let actor = model.modelActor() else { return }
        let id = model.id
        Task.detached {
            await actor.setup(id: id)
            let fileUrl = try? await fileController.fileUrlDataController.duplicate(fileUrl: actor.fileUrl, for: newId)
            await actor.duplicate(url: fileUrl?.rawUrl)
            await actor.save()
        }
    }
    
    func delete(model: AudioDataModel) {
        let fileUrl = model.fileUrl
        let modelContext = model.modelContext
        Task.detached {
            await fileController.fileUrlDataController.delete(fileUrl)
        }
        model.entryModels.forEach { entry in
            if let entryItem = AudioDataModel.model(modelContext: modelContext, id: entry.itemId) {
                if model.category == .folder {
                    entryItem.parentId = model.parentId
                }
                entryItem.displayState = 0
            }
        }
        modelContext?.delete(model)
        updateTags(modelContext: modelContext)
        try? modelContext?.save()
    }
        
    func addItem(itemId: UUID, in model: AudioDataModel) {
        guard itemId != model.id else { return }
        model.withTransaction { modelContext in
            guard let item = AudioDataModel.model(modelContext: modelContext, id: itemId) else { return }
            
            var entries: [AudioEntryDataModel] = model.entryModels
            let entry = AudioEntryDataModel(id: UUID(), index: Int16(entries.count), parentId: model.id, itemId: itemId, item: model)
            entries.append(entry)
            model.entryModels = entries
            modelContext.insert(entry)
            if model.category == .folder {
                item.parentId = model.id
            }
        }
    }

    func removeItem(itemId: UUID, model: AudioDataModel) {
        model.withTransaction { modelContext in
            guard let item = AudioDataModel.model(modelContext: modelContext, id: itemId) else { return }
            
            let entry = model[itemId]
            model.entryModels.removeAll(where: { $0.itemId == itemId })
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

    func update(model: AudioDataModel, name: String, information: String, category: ItemListCategory, tags: [String]) {
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
        let fetch = FetchDescriptor<AudioDataModel>()
        guard let models = try? modelContext.fetch(fetch) else { return }
        let tags = Set(models.flatMap { $0.tags })
        TagController.update(tags: tags, in: AudioDataModel.typeId, modelContext: modelContext)
    }
}

// MARK: - File Editor
extension EditController {
    func resetFile(url: URL?, in model: AudioDataModel) {
        guard let actor = model.modelActor() else { return }
        let id = model.id
        Task.detached {
            await actor.setup(id: id)
            await resetFile(url: url, id: id, actor: actor)
            await actor.save()
        }
    }
    
    private func resetFile(url: URL?, id: UUID, actor: DataModelActor) async {
        await fileController.fileUrlDataController.delete(await actor.fileUrl)
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
        let updatedFileUrl = try? await fileController.fileUrlDataController.createFileUrl(fileId: id, url: url, module: AudioDataModel.typeId.token, category: actor.category.title)
        await actor.update(url: updatedFileUrl?.rawUrl)
    }
}
