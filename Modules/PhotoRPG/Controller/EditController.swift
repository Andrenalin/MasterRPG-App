// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData
internal import UIKit

struct EditController {
    let root: PhotoRootModel
    
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
        await root.fileController.fileUrlDataController.delete(await actor.fileUrl)
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
        let updatedFileUrl = try? await root.fileController.fileUrlDataController.createFileUrl(fileId: id, url: url, module: root.networkModule.token, category: actor.category.title)
        await actor.update(url: updatedFileUrl?.rawUrl)
    }
    
        func resetPhoto(data: Data?, id: UUID, actor: PhotoDataModelActor) async {
            await root.fileController.fileUrlDataController.delete(await actor.fileUrl)
            await actor.update(url: nil)
            guard let data else { return }
    
            let module = root.networkModule.token
            let filePath = await actor.name.isEmpty ? "\(await actor.category.title)/Image-\(id.uuidString).jpg" : "\(await actor.category.title)/\(await actor.name).jpg"
            var dataFileUrl = FileUrl(fileId: id, url: URL(string: filePath)!, location: .cloud, module: module)
            dataFileUrl.resetData(data)
    
            let updatedFileUrl = try? await root.fileController.fileUrlDataController.createNewFileUrl(fileId: id, unconvertedFileUrl: dataFileUrl, pathExtension: "jpg")
            await actor.update(url: updatedFileUrl?.rawUrl)
        }

    //    private func resetFileUrl() async {
    //        await root.itemController.didDelete(fileUrl: model.fileUrl)
    //        await model.fileUrl = nil
    //    }
    //
    //
    //
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
