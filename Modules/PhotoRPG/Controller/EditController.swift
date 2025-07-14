// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

@ModelActor
actor PhotoModelActor {
    func update(name: String, for id: UUID) {
        model(for: id)?.name = name
    }
    
    func update(url: URL?, for id: UUID) {
        model(for: id)?.url = url
    }

    func save() {
        try? modelContext.save()
    }

    private func model(for id: UUID) -> PhotoDataModel? {
        PhotoDataModel.model(modelContext: modelContext, id: id)
    }
}

actor EditModel {
    init(id: UUID, name: String, category: ItemListCategory, fileUrl: FileUrl?, url: URL?) {
        self.id = id
        self.name = name
        self.category = category
        self.fileUrl = fileUrl
        self.url = url
    }
    
    let id: UUID
    var name: String
    let category: ItemListCategory
    let fileUrl: FileUrl?
    var url: URL?
    
    func reset(name: String) {
        self.name = name
    }
    
    func reset(url: URL?) {
        self.url = url
    }
}

struct EditController {
    let root: PhotoRootModel
    
    // import from file browser
    func resetPhoto(url: URL?, in model: PhotoDataModel) {
        guard let container = model.modelContext?.container else { return }
        let actor = PhotoModelActor(modelContainer: container)
        let editModel = EditModel(id: model.id, name: model.name, category: model.category, fileUrl: model.fileUrl, url: model.url)
        Task.detached {
            let updatedEditModel = await resetPhoto(url: url, for: editModel)
            let updatedUrl = await updatedEditModel.url
            let updatedName = await updatedEditModel.name
            await actor.update(url: updatedUrl, for: updatedEditModel.id)
            await actor.update(name: updatedName, for: updatedEditModel.id)
            await actor.save()
        }
    }
    
    private func resetPhoto(url: URL?, for model: EditModel) async -> EditModel {
        root.fileController.fileUrlDataController.delete(model.fileUrl)
        guard let url else {
            await model.reset(url: url)
            return model
        }
        _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }
        
        if await model.name.isEmpty {
            let ext = url.pathExtension.isEmpty ? "" : ".\(url.pathExtension)"
            let name = url.lastPathComponent.replacingOccurrences(of: ext, with: "")
            await model.reset(name: name)
        }
        let fileUrl = try? await root.fileController.fileUrlDataController.createFileUrl(fileId: model.id, url: url, module: root.networkModule.token, category: model.category.title)
        await model.reset(url: fileUrl?.rawUrl)
        return model
    }
    
    
    //    private func resetFileUrl() async {
    //        await root.itemController.didDelete(fileUrl: model.fileUrl)
    //        await model.fileUrl = nil
    //    }
    //
    //    func resetPhoto(image: AKImage?) async {
    //        let data = image?.jpegData(compressionQuality: 0.9)
    //        await resetPhoto(data: data)
    //    }
    //
    //    func resetPhoto(data: Data?) async {
    //        try? await resetPhotoJob(data: data)
    //    }
    //
    //    func resetPhotoJob(data: Data?) async throws {
    //        await resetFileUrl()
    //        guard let data else { return }
    //
    //        let module = await root.itemController.itemDataModel.networkModule.token
    //        let filePath = await model.name.isEmpty ? "\(await model.category.title)/Image-\(model.id.uuidString).jpg" : "\(await model.category.title)/\(await model.name).jpg"
    //        var dataFileUrl = await FileUrl(fileId: model.id, url: URL(string: filePath)!, location: .newCloud, module: module, relativeUrl: nil)
    //        dataFileUrl.resetData(data)
    //
    //        let fileUrl = try await root.fileUrlDataController.createNewFileUrl(fileId: model.id, unconvertedFileUrl: dataFileUrl, pathExtension: "jpg")
    //
    //        let saveTask = Task { @MainActor in
    //            model.fileUrl = fileUrl
    //            save(with: String(localized: "New Photo").localizedString)
    //        }
    //        _ = await saveTask.result
    //    }
    //
    //
    //    func resetPhoto(url: URL?, into itemId: UUID) async {
    //        let item = await model.id == itemId ? model : root.itemController.item(for: itemId)?.copy()
    //        guard let item else { return }
    //        await resetPhoto(url: url, for: item, undoSave: model.id == itemId)
    //    }
    //
    
    //
    
}
