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
    func addNew(modelContext: ModelContext) -> PhotoDataModel {
        let newItem = PhotoDataModel.newItem
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
    
    func delete(model: any Identifiable) {
        guard let model = model as? PhotoDataModel else { return }
        let fileUrl = model.fileUrl
        let modelContext = model.modelContext
        Task.detached {
            await fileController.fileUrlDataController.delete(fileUrl)
        }
        modelContext?.delete(model)
        updateTags(modelContext: modelContext)
        try? modelContext?.save()
    }
    
    func addSubPhoto(photoId: UUID, model: PhotoDataModel) {
        model.withTransaction {
            var entries: [PhotoEntryDataModel] = model.entryModels

            let entry = PhotoEntryDataModel(id: UUID(), index: Int16(entries.count), parentId: model.id, photoId: photoId, photo: model)
            entries.append(entry)
            model.entryModels = entries
            
            guard let modelContext = model.modelContext, let subModel = PhotoDataModel.model(modelContext: modelContext, id: photoId) else { return }
            modelContext.insert(entry)
            subModel.displayState = DisplayStateMask.totalHidden.rawValue
        }
    }

    func removeSubPhoto(photoId: UUID, model: PhotoDataModel) {
        model.withTransaction {
            let entry = model[photoId]
            model.entryModels.removeAll(where: { $0.photoId == photoId })
            model.entryModels.enumerated().forEach { index, entry in
                entry.index = Int16(index)
            }
                        
            guard let modelContext = model.modelContext, let subModel = PhotoDataModel.model(modelContext: modelContext, id: photoId) else { return }
            modelContext.delete(entry)
            subModel.displayState = 0
        }
    }

    func update(model: PhotoDataModel, name: String, information: String, category: ItemListCategory, tags: [String], degrees: Double) {
        model.withTransaction {
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
        let filePath = await actor.name.isEmpty ? "\(await actor.category.title)/Image-\(id.uuidString).jpg" : "\(await actor.category.title)/\(await actor.name).jpg"
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
