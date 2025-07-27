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
    typealias Model = SpaceDataModel
}

// MARK: - Edit Photo Data Model Properties
extension EditController {
    func addNew(modelContext: ModelContext) -> SpaceDataModel {
        let newItem = SpaceDataModel.newItem
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
            let fileUrl = try? await fileController.fileUrlDataController.duplicate(fileUrl: actor.fileUrl, for: newId)
            await actor.duplicate(url: fileUrl?.rawUrl)
            await actor.save()
        }
    }
    
    func delete(model: any Identifiable) {
        guard let model = model as? SpaceDataModel else { return }
        let fileUrl = model.fileUrl
        let modelContext = model.modelContext
        Task.detached {
            await fileController.fileUrlDataController.delete(fileUrl)
        }
        modelContext?.delete(model)
        updateTags(modelContext: modelContext)
        try? modelContext?.save()
    }
    
    func addSubPhoto(photoId: UUID, model: SpaceDataModel) {
        model.withTransaction {
            var entries: [SpaceEntryDataModel] = model.entryModels
            
            let entry = SpaceEntryDataModel(id: UUID(), index: Int16(entries.count), parentId: model.id, spaceId: photoId, space: model)
            entries.append(entry)
            model.entryModels = entries
            
            guard let modelContext = model.modelContext, let subModel = SpaceDataModel.model(modelContext: modelContext, id: photoId) else { return }
            modelContext.insert(entry)
            subModel.displayState = DisplayStateMask.totalHidden.rawValue
        }
    }
    
    func removeSubPhoto(photoId: UUID, model: SpaceDataModel) {
        model.withTransaction {
            let entry = model[photoId]
            model.entryModels.removeAll(where: { $0.spaceId == photoId })
            model.entryModels.enumerated().forEach { index, entry in
                entry.index = Int16(index)
            }
            
            guard let modelContext = model.modelContext, let subModel = SpaceDataModel.model(modelContext: modelContext, id: photoId) else { return }
            modelContext.delete(entry)
            subModel.displayState = 0
        }
    }
    
    func update(model: SpaceDataModel, name: String, information: String, category: ItemListCategory, tags: [String]) {
        model.withTransaction {
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

    // import from file browser
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
        let updatedFileUrl = try? await fileController.fileUrlDataController.createFileUrl(fileId: id, url: url, module: SpaceDataModel.typeId.token, category: actor.category.title)
        await actor.update(url: updatedFileUrl?.rawUrl)
    }
}
