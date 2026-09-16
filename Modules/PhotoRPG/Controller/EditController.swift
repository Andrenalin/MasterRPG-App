// @copyright André Trettin

import CoreRPG
import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct EditController: Sendable {
    @MainActor init(itemController: ItemController, linkController: LinkController, sheetController: SheetController, tagController: TagController) {
        self.tagController = tagController
        self.itemController = itemController
        let sheetEditorModel = SheetEditorModel(module: itemController.config.module)
        let editorModel = ItemEditorModel(sheetEditorModel: sheetEditorModel)
        self.editorModel = editorModel
    }

    let itemController: ItemController
    let tagController: TagController
    let editorModel: ItemEditorModel
}

extension EditController: EditControllable {
    typealias Model = PhotoModel

    var cacheController: CacheController? { itemController.cacheController }
    var itemControllable: any ItemControllable { itemController }
}

extension EditController {
    @MainActor func convert(itemId: UUID) async throws {
        guard let item = editModel(for: itemId), let fileUrl = item.fileUrl else { return }
        await cacheController?.photoId(for: item.id, item: item, shouldDownload: true)
        guard let image = await cacheController?.photo(for: item.id), let data = image.jpegData(compressionQuality: JPEGQuality.export) else { return }

        var dataUrl = fileUrl
        dataUrl.convertFile(data, fileExtension: itemController.config.filenameExtension)

        let newFileUrl = try await fileUrlDataController?.createNewFileUrl(fileId: item.id, unconvertedFileUrl: dataUrl, pathExtension: itemController.config.filenameExtension)
        await itemControllable.cacheControllable?.remove(itemId: itemId)
        reset(fileUrl: newFileUrl, itemId: item.id)
    }
    
    @MainActor func isNotJpegPhoto(itemId: UUID) -> Bool {
        guard let item = editModel(for: itemId) else { return false }
        guard let fileUrl = item.fileUrl else { return false }
        return !(fileUrl.fileExtension == itemController.config.filenameExtension || fileUrl.fileExtension == "jpeg")
    }

    func loadImage(cacheType: CacheItemListModel.CacheType, item: Model, itemId: UUID, fileUrl: FileUrl?, reset: Bool = false) async -> AKImage? {
        guard let cacheController, fileUrl != nil else { return nil }
        if reset {
            await cacheController.setCachedImage(nil, for: itemId)
            await cacheController.setCachedThumbnail(nil, for: itemId)
        }
        if let newImage = cacheType == .image ? await cacheController.cachedImage(for: itemId) : await cacheController.cachedThumbnail(for: itemId) {
            return newImage
        }
        var result: AKImage? = nil
        if cacheType == .image {
            await cacheController.photoId(for: itemId, item: item, shouldDownload: true)
            result = await cacheController.photo(for: itemId)
            
            await cacheController.setCachedImage(result, for: itemId)
        }
        await cacheController.thumbnailId(for: itemId, item: item)
        let newThumbnail = await cacheController.thumbnail(for: itemId)
        // Full-resolution detail loading must not clear a list thumbnail when a
        // thumbnail refresh is temporarily unavailable or the task is cancelled.
        if let newThumbnail {
            await cacheController.setCachedThumbnail(newThumbnail, for: itemId)
        }
        return cacheType == .image ? result : newThumbnail
    }
        
    func resetPhoto(image: AKImage?, itemId: UUID) async throws {
        let data = image?.jpegData(compressionQuality: JPEGQuality.export)
        try await resetFile(data: data, itemId: itemId, path: "")
    }
}
