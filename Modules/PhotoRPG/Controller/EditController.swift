// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData
internal import UIKit

struct EditController {
    let fileController: FileController
    let networkModule: NetworkModules = .photo
}

// MARK: - Edit Photo Data Model Properties
extension EditController {
    func copy(model: PhotoDataModel) {
        let newId = UUID()
        guard let actor = model.modelActor() else { return }
        let id = model.id
        Task.detached {
            await actor.setup(id: id)
            let fileUrl = try? await fileController.fileUrlDataController.duplicate(fileUrl: actor.fileUrl, for: newId)
            await actor.duplicate(id: id, url: fileUrl?.rawUrl)
            await actor.save()
        }
    }
    
    func delete(model: PhotoDataModel) {
        let fileUrl = model.fileUrl
        model.modelContext?.delete(model)
        Task.detached {
            await fileController.fileUrlDataController.delete(fileUrl)
        }
    }
    
    func addSubPhoto(photoId: UUID, model: PhotoDataModel) {
        model.withTransaction {
            var entries: [PhotoEntryDataModel] = model.entries

            let entry = PhotoEntryDataModel(id: UUID(), index: Int16(entries.count), parentId: model.id, photoId: photoId, photo: model)
            entries.append(entry)
            model.entries = entries
            
            guard let modelContext = model.modelContext, let subModel = PhotoDataModel.model(modelContext: modelContext, id: photoId) else { return }
            modelContext.insert(entry)
            subModel.displayState = DisplayStateMask.totalHidden.rawValue
        }
    }

    func removeSubPhoto(photoId: UUID, model: PhotoDataModel) {
        model.withTransaction {
            guard let entry = model.entries.first(where: { $0.photoId == photoId }) else { return }
            model.entries.removeAll(where: { $0.photoId == photoId })
            model.entries.enumerated().forEach { index, entry in
                entry.index = Int16(index)
            }
                        
            guard let modelContext = model.modelContext, let subModel = PhotoDataModel.model(modelContext: modelContext, id: photoId) else { return }
            modelContext.delete(entry)
            subModel.displayState = 0
        }
    }

    func update(model: PhotoDataModel, name: String, information: String, category: ItemListCategory, tags: [String], degrees: Double) {
        if let modelContext = model.modelContext {
            do {
                try modelContext.transaction {
                    updateInternal(model: model, name: name, information: information, category: category, tags: tags, degrees: degrees)
                }
            } catch {
                modelContext.rollback()
            }
        } else {
            updateInternal(model: model, name: name, information: information, category: category, tags: tags, degrees: degrees)
        }
    }
    
    private func updateInternal(model: PhotoDataModel, name: String, information: String, category: ItemListCategory, tags: [String], degrees: Double) {
        model.reset(name: name)
        model.reset(information: information)
        model.category = category
        model.tags = tags
        model.degrees = degrees
    }
}


// MARK: - Photo image editor
extension EditController {
    
    // import from file browser
    func resetPhoto(url: URL?, in model: PhotoDataModel) {
        guard let actor = model.modelActor() else { return }
        let id = model.id
        Task.detached {
            await actor.setup(id: id)
            await resetPhoto(url: url, id: id, actor: actor)
            await actor.save()
        }
    }
    
    func resetPhoto(image: AKImage?, id: UUID, actor: PhotoDataModelActor) async {
        let data = image?.jpegData(compressionQuality: 0.9)
        await actor.setup(id: id)
        await resetPhoto(data: data, id: id, actor: actor)
        await actor.save()
    }
    
    
    private func resetPhoto(url: URL?, id: UUID, actor: PhotoDataModelActor) async {
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
        let updatedFileUrl = try? await fileController.fileUrlDataController.createFileUrl(fileId: id, url: url, module: networkModule.token, category: actor.category.title)
        await actor.update(url: updatedFileUrl?.rawUrl)
    }
    
    private func resetPhoto(data: Data?, id: UUID, actor: PhotoDataModelActor) async {
        await fileController.fileUrlDataController.delete(await actor.fileUrl)
        await actor.update(url: nil)
        guard let data else { return }
        
        let module = networkModule.token
        let filePath = await actor.name.isEmpty ? "\(await actor.category.title)/Image-\(id.uuidString).jpg" : "\(await actor.category.title)/\(await actor.name).jpg"
        var dataFileUrl = FileUrl(fileId: id, url: URL(string: filePath)!, location: .cloud, module: module)
        dataFileUrl.resetData(data)
        
        let updatedFileUrl = try? await fileController.fileUrlDataController.createNewFileUrl(fileId: id, unconvertedFileUrl: dataFileUrl, pathExtension: "jpg")
        await actor.update(url: updatedFileUrl?.rawUrl)
    }
}
