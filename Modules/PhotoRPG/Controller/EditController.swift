// @copyright André Trettin

import AndrenalinKit
import Foundation
import Observation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct EditController: Sendable {
    @MainActor init(itemController: ItemController, linkRegisterControllable: LinkRegisterControllable, currentListItem: ItemRowTreeModel?, currentModel: (ModelType)?) {
        self.linkRegisterControllable = linkRegisterControllable
        self.itemController = itemController
        self.editorModel = ItemEditorModel(currentListItem: currentListItem, currentModel: currentModel)
    }

    let itemController: ItemController
    let linkRegisterControllable: any LinkRegisterControllable
    let editorModel: ItemEditorModel
}

extension EditController: EditControllable {
    typealias Model = PhotoModel

    var itemControllable: any ItemControllable {
        itemController
    }
    
    var cacheController: CacheController? {
        itemController.cacheController
    }
    
    var fileUrlDataController: FileUrlDataController? {
        itemControllable.fileUrlDataController
    }
}

extension EditController {
    func reset(fileUrl: FileUrl, for itemId: UUID) async {
        let item = await itemId == model.id ? model : itemController.itemOrEmpty(for: itemId).copy()
        item.fileUrl = fileUrl
        if await itemId == model.id {
            await save(with: "")
        } else {
            await itemController.replace(model: item, isInsert: false, shouldRepairLinks: false)
        }
    }
}

extension EditController {
    func convert() async throws {
        await cacheController?.photoId(for: model.id, item: model, shouldDownload: true)
        guard let image = await cacheController?.photo(for: model.id), let data = image.jpegData(compressionQuality: 0.9), let fileUrl = await model.fileUrl else { return }

        await resetFileUrl()
        var dataUrl = fileUrl
        dataUrl.convertFile(data, fileExtension: "jpg")

        let newFileUrl = try await fileUrlDataController?.createNewFileUrl(fileId: model.id, unconvertedFileUrl: dataUrl, pathExtension: "jpg")

        Task { @MainActor in
            model.fileUrl = newFileUrl
            save(with: String(localized: "New Photo").localizedString)
        }
    }
    
    func loadImage(cacheType: CacheItemListModel.CacheType, itemId: UUID, fileUrl: FileUrl?, reset: Bool = false) async -> AKImage? {
        guard fileUrl != nil, let item = await itemController.itemSync(for: itemId) else { return nil }
        if reset {
            await cacheItemListModel.setImageCache(cacheType: .image, itemId: itemId, image: nil)
            await cacheItemListModel.setImageCache(cacheType: .thumbnail, itemId: itemId, image: nil)
        }
        if let newImage = await cacheItemListModel.imageCache(cacheType: cacheType, itemId: itemId) {
            return newImage
        }
        var result: AKImage? = nil
        if cacheType == .image {
            await cacheController?.photoId(for: itemId, item: item, shouldDownload: true)
            result = await cacheController?.photo(for: itemId)
            
            await cacheItemListModel.setImageCache(cacheType: .image, itemId: itemId, image: result)
        }
        await cacheController?.thumbnailId(for: itemId, item: item)
        let newThumbnail = await cacheController?.thumbnail(for: itemId)
        await cacheItemListModel.setImageCache(cacheType: .thumbnail, itemId: itemId, image: newThumbnail)
        return cacheType == .image ? result : newThumbnail
    }
    
    private func resetFileUrl() async {
        await itemController.didDelete(fileUrl: model.fileUrl)
        await model.fileUrl = nil
    }
    
    func resetPhoto(image: AKImage?) async {
        let data = image?.jpegData(compressionQuality: 0.9)
        await resetPhoto(data: data)
    }

    func resetPhoto(data: Data?) async {
        try? await resetPhotoJob(data: data)
    }
    
    func resetPhotoJob(data: Data?) async throws {
        await resetFileUrl()
        guard let data else { return }
        
        let module = await itemController.itemDataModel.networkModule.token
        let filePath = await model.name.isEmpty ? "\(await model.category.title)/Image-\(model.id.uuidString).jpg" : "\(await model.category.title)/\(await model.name).jpg"
        var dataFileUrl = await FileUrl(fileId: model.id, url: URL(string: filePath)!, location: .newCloud, module: module, relativeUrl: nil)
        dataFileUrl.resetData(data)
        
        let fileUrl = try await fileUrlDataController?.createNewFileUrl(fileId: model.id, unconvertedFileUrl: dataFileUrl, pathExtension: "jpg")

        let saveTask = Task { @MainActor in
            model.fileUrl = fileUrl
            save(with: String(localized: "New Photo").localizedString)
        }
        _ = await saveTask.result
    }

    func resetPhoto(url: URL?) {
        Task { @MainActor in
            await resetPhoto(url: url, for: model, undoSave: true)
        }
    }

    func resetPhoto(url: URL?, into itemId: UUID) async {
        let item = await model.id == itemId ? model : itemController.item(for: itemId)?.copy()
        guard let item else { return }
        await resetPhoto(url: url, for: item, undoSave: model.id == itemId)
    }

    private func resetPhoto(url: URL?, for item: PhotoModel, undoSave: Bool) async {
        guard let fileUrlDataController else { return }
        await itemController.didDelete(fileUrl: item.fileUrl)
        await resetURL(url: nil, on: item)
        guard let url else {
            if undoSave {
                await save(with: String(localized: "Remove Photo").localizedString)
            } else {
                await itemController.replace(model: item, isInsert: false, shouldRepairLinks: true)
            }
            return
        }
        _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }

        if item.name.isEmpty {
            let ext = url.pathExtension.isEmpty ? "" : ".\(url.pathExtension)"
            let name = url.lastPathComponent.replacingOccurrences(of: ext, with: "")
            let saveName = Task { @MainActor in
                item.name = name
            }
            _ = await saveName.value
        }
        let fileUrl = try? await fileUrlDataController.createFileUrl(fileId: item.id, url: url, module: itemController.itemDataModel.networkModule.token, category: item.category.title)
        await resetURL(url: fileUrl, on: item)
        if undoSave {
            await save(with: String(localized: "New Photo").localizedString)
        } else {
            await itemController.replace(model: item, isInsert: false, shouldRepairLinks: true)
        }
    }
    
    private func resetURL(url: FileUrl?, on item: PhotoModel) async {
        let saveTask = Task { @MainActor in
            item.fileUrl = url
        }
        await saveTask.value
    }

    @MainActor
    func isNotJpegPhoto() -> Bool {
        guard let fileUrl = model.fileUrl else { return false }
        return !(fileUrl.fileExtension == "jpg" || fileUrl.fileExtension == "jpeg")
    }
}
