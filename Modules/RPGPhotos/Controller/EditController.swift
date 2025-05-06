// @copyright André Trettin

import AndrenalinKit
import Foundation
import Observation
#if os(macOS)
internal import AppKit
#else
internal import UIKit
#endif

struct EditController: Sendable {
    @MainActor
    init(root: PhotoRoot, currentListItem: ItemRowTreeModel?, currentModel: (ModelType)?) {
        self.root = root
        self.editorModel = ItemEditorModel(currentListItem: currentListItem, currentModel: currentModel)
    }

    weak var root: PhotoRoot!
    let editorModel: ItemEditorModel
}

extension EditController: EditControllable {
    typealias Model = PhotoModel

    var itemControllable: any ItemControllable {
        root.itemController as (any ItemControllable)
    }

    var rootControllable: any RootControllable {
        root.rootControllable
    }
}

extension EditController {
    @MainActor func reset(category: ItemListCategory) {
        guard model.category != category else { return }
        let oldCategory = model.category
        let oldFileUrl = model.fileUrl
        model.category = category
        let saveModel = model
        Task { @MainActor in
            let newFileUrl = await root.fileUrlDataController.move(fileUrl: oldFileUrl, from: oldCategory, to: category)
            if let newFileUrl {
                saveModel.fileUrl = newFileUrl
            }
            save(with: String(localized: "Change to \(category.title)").localizedString)
        }
    }

    @MainActor func reset(name: String) {
        guard model.name != name else { return }
        let oldName = model.name
        let oldFileUrl = model.fileUrl
        model.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        editorModel.cacheItemListModel.reset(cacheType: .name, itemId: model.id, text: model.name.markDownText())
        let saveModel = model
        Task { @MainActor in
            let newFileUrl = await root.fileUrlDataController.move(fileUrl: oldFileUrl, from: oldName, to: saveModel.name)
            if let newFileUrl {
                saveModel.fileUrl = newFileUrl
            }
            save(with: String(localized: "Typing").localizedString)
        }
    }
}

extension EditController {
    func convert() async throws {
        await root.cacheController.photoId(for: model.id, with: model.fileUrl, shouldDownload: true)
        guard let image = await root.cacheController.image(for: model.id), let data = image.jpegData(compressionQuality: 0.9), let fileUrl = await model.fileUrl else { return }

        await resetFileUrl()
        var dataUrl = fileUrl
        dataUrl.convertFile(data, fileExtension: "jpg")

        let newFileUrl = try await root.fileUrlDataController.createNewFileUrl(fileId: model.id, unconvertedFileUrl: dataUrl, pathExtension: "jpg",)

        Task { @MainActor in
            model.fileUrl = newFileUrl
            save(with: String(localized: "New Photo").localizedString)
        }
    }
    
    func loadImage(cacheType: CacheItemListModel.CacheType, itemId: UUID, fileUrl: FileUrl?, reset: Bool = false) async -> AKImage? {
        guard let fileUrl else { return nil }
        if reset {
            await cacheItemListModel.setImageCache(cacheType: .image, itemId: itemId, image: nil)
            await cacheItemListModel.setImageCache(cacheType: .thumbnail, itemId: itemId, image: nil)
        }
        if let newImage = await cacheItemListModel.imageCache(cacheType: cacheType, itemId: itemId) {
            return newImage
        }
        var result: AKImage? = nil
        if cacheType == .image {
            await root.cacheController.photoId(for: itemId, with: fileUrl, shouldDownload: true)
            result = await root.cacheController.image(for: itemId)
            
            await cacheItemListModel.setImageCache(cacheType: .image, itemId: itemId, image: result)
        }
        await root.cacheController.thumbnailId(for: itemId, with: fileUrl)
        let newThumbnail = await root.cacheController.thumbnail(for: itemId)
        await cacheItemListModel.setImageCache(cacheType: .thumbnail, itemId: itemId, image: newThumbnail)
        return cacheType == .image ? result : newThumbnail
    }
    
    private func resetFileUrl() async {
        await root.itemController.didDelete(fileUrl: model.fileUrl)
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
        
        let module = await root.itemController.itemDataModel.networkModule.token
        let filePath = await model.name.isEmpty ? "\(await model.category.title)/Image-\(model.id.uuidString).jpg" : "\(await model.category.title)/\(await model.name).jpg"
        var dataFileUrl = await FileUrl(fileId: model.id, url: URL(string: filePath)!, location: .newCloud, module: module, relativeUrl: nil)
        dataFileUrl.resetData(data)
        
        let fileUrl = try await root.fileUrlDataController.createNewFileUrl(fileId: model.id, unconvertedFileUrl: dataFileUrl, pathExtension: "jpg")

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
        let item = await model.id == itemId ? model : root.itemController.item(for: itemId)?.copy()
        guard let item else { return }
        await resetPhoto(url: url, for: item, undoSave: model.id == itemId)
    }

    private func resetPhoto(url: URL?, for item: PhotoModel, undoSave: Bool) async {
        await root.itemController.didDelete(fileUrl: item.fileUrl)
        await resetURL(url: nil, on: item)
        guard let url else {
            if undoSave {
                await save(with: String(localized: "Remove Photo").localizedString)
            } else {
                await root.itemController.replace(model: item, isInsert: false, shouldRepairLinks: true)
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
        let fileUrl = try? await root.fileUrlDataController.createFileUrl(fileId: item.id, url: url, module: root.itemController.itemDataModel.networkModule.token, category: item.category.title)
        await resetURL(url: fileUrl, on: item)
        if undoSave {
            await save(with: String(localized: "New Photo").localizedString)
        } else {
            await root.itemController.replace(model: item, isInsert: false, shouldRepairLinks: true)
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
