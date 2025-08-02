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
    typealias Model = PhotoDataModel
}

// MARK: - Edit Data Model Properties
extension EditController {
    @MainActor func addNew(modelContext: ModelContext, type: EditControllerAddType) -> PhotoDataModel {
        let newItem = PhotoDataModel.newItem
        if type == .folder {
            newItem.category = .folder
        } else if type == .collection {
            newItem.category = PhotoDataModel.collectionCategory
        }
        modelContext.insert(newItem)
        try? modelContext.save()
        return newItem
    }
    
    func duplicate(model: PhotoDataModel) {
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
    
    func delete(model: PhotoDataModel) {
        let fileUrl = model.fileUrl
        let modelContext = model.modelContext
        Task.detached {
            await fileController.fileUrlDataController.delete(fileUrl)
        }
        model.entryModels.forEach { entry in
            if let entryItem = PhotoDataModel.model(modelContext: modelContext, id: entry.itemId) {
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
        guard let model = PhotoDataModel.model(modelContext: modelContext, id: parentId) else { return }
        addItem(itemId: itemId, in: model, folderId: folderId)
    }
    
    func addItem(itemId: UUID, in model: PhotoDataModel, folderId: UUID?) {
        guard itemId != model.id else { return }
        model.withTransaction { modelContext in
            guard let item = PhotoDataModel.model(modelContext: modelContext, id: itemId) else { return }
            
            var entries: [PhotoEntryDataModel] = model.entryModels
            let entry = PhotoEntryDataModel(id: UUID(), index: Int16(entries.count), parentId: model.id, itemId: itemId, item: model)
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

    func removeItem(itemId: UUID, model: PhotoDataModel) {
        model.withTransaction { modelContext in
            guard let item = PhotoDataModel.model(modelContext: modelContext, id: itemId) else { return }
            
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

    func addSubPhoto(photoId: UUID, model: PhotoDataModel) {
        model.withTransaction { modelContext in
            var entries: [PhotoEntryDataModel] = model.entryModels

            let entry = PhotoEntryDataModel(id: UUID(), index: Int16(entries.count), parentId: model.id, itemId: photoId, item: model)
            entries.append(entry)
            model.entryModels = entries
            
            guard let subModel = PhotoDataModel.model(modelContext: modelContext, id: photoId) else { return }
            modelContext.insert(entry)
            subModel.displayState = DisplayStateMask.totalHidden.rawValue
        }
    }

    func removeSubPhoto(photoId: UUID, model: PhotoDataModel) {
        model.withTransaction { modelContext in
            let entry = model[photoId]
            model.entryModels.removeAll(where: { $0.itemId == photoId })
            model.entryModels.enumerated().forEach { index, entry in
                entry.index = Int16(index)
            }
                        
            guard let subModel = PhotoDataModel.model(modelContext: modelContext, id: photoId) else { return }
            modelContext.delete(entry)
            subModel.displayState = 0
        }
    }

    func update(model: PhotoDataModel, name: String, information: String, category: CoreRPG.ItemListCategory, tags: [String]) {
        update(model: model, name: name, information: information, category: category, tags: tags, degrees: model.degrees)
    }

    func update(model: PhotoDataModel, name: String, information: String, category: ItemListCategory, tags: [String], degrees: Double) {
        model.withTransaction { modelContext in
            model.reset(name: name)
            model.reset(information: information)
            model.category = category
            model.tags = tags
            model.degrees = degrees
        }
        
        updateTags(modelContext: model.modelContext)
    }
    
    func updateTags(modelContext: ModelContext?) {
        guard let modelContext else { return }
        let fetch = FetchDescriptor<PhotoDataModel>()
        guard let models = try? modelContext.fetch(fetch) else { return }
        let tags = Set(models.flatMap { $0.tags })
        TagController.update(tags: tags, in: PhotoDataModel.typeId, modelContext: modelContext)
    }
}

// MARK: - File Editor
extension EditController {
    func resetFile(url: URL?, in model: PhotoDataModel) {
        guard let actor = model.modelActor() else { return }
        let id = model.id
        Task.detached {
            await actor.setup(id: id)
            await resetFile(url: url, id: id, actor: actor)
            await actor.save()
        }
    }
    
    func resetFile(image: AKImage?, id: UUID, actor: DataModelActor) async {
        guard let image else { return }
        let data = image.jpegData(compressionQuality: 0.9)
        await actor.setup(id: id)
        await resetFile(data: data, id: id, actor: actor)
        await actor.save()
    }

    func resetFile(data: Data, model: PhotoDataModel) {
        guard let actor = model.modelActor() else { return }
        let id = model.id
        Task.detached {
            await actor.setup(id: id)
            await resetFile(data: data, id: id, actor: actor)
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
        let updatedFileUrl = try? await fileController.fileUrlDataController.createFileUrl(fileId: id, url: url, module: PhotoDataModel.typeId.token, category: actor.category.title)
        await actor.update(url: updatedFileUrl?.rawUrl)
    }
    
    private func resetFile(data: Data?, id: UUID, actor: DataModelActor) async {
        await fileController.fileUrlDataController.delete(await actor.fileUrl)
        await actor.update(url: nil)
        guard let data else { return }
        
        let module = PhotoDataModel.typeId.token
        let filePath = await actor.name.isEmpty ? "\(await actor.category.title)/Image-\(id.uuidString).\(FileController.filenameExtension)" : "\(await actor.category.title)/\(await actor.name).\(FileController.filenameExtension)"
        var dataFileUrl = FileUrl(fileId: id, url: URL(string: filePath)!, location: .cloud, module: module)
        dataFileUrl.resetData(data)
        
        let updatedFileUrl = try? await fileController.fileUrlDataController.createNewFileUrl(fileId: id, unconvertedFileUrl: dataFileUrl, pathExtension: FileController.filenameExtension)
        await actor.update(url: updatedFileUrl?.rawUrl)
    }
}

extension EditController {
#if os(macOS)
    static let importImageTypes = AKImage.imageTypes.compactMap { UTType($0) }

    nonisolated
    static func importImageFromProviders(_ itemProviders: [NSItemProvider], completion: @Sendable @escaping (Data?) -> Void) -> Bool {
        guard let provider = itemProviders.first else { return false }
        for type in importImageTypes {
            let typeIdentifier = type.identifier
            if provider.hasItemConformingToTypeIdentifier(typeIdentifier) {
                provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
                    DispatchQueue.main.async {
                        completion(data)
                    }
                }
                return true
            }
        }
        return false
    }
#endif
}
