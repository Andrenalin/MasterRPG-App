// @copyright André Trettin

import CoreRPG
import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct EditController: Sendable {
    @MainActor init(itemController: ItemController, linkRegisterController: LinkRegisterController, tagController: TagController) {
        self.linkRegisterController = linkRegisterController
        self.tagController = tagController
        self.itemController = itemController
        self.editorModel = ItemEditorModel()
    }

    let itemController: ItemController
    let linkRegisterController: LinkRegisterController
    let tagController: TagController
    let editorModel: ItemEditorModel
}

extension EditController: EditControllable {
    typealias Model = PhotoModel

    var cacheController: CacheController? { itemController.cacheController }
    var itemControllable: any ItemControllable { itemController }
    var fileUrlDataController: FileUrlDataController? { itemController.fileUrlDataController }
}

extension EditController {
    func convert(itemId: UUID) async throws {
        guard let item = await editModel(for: itemId), let fileUrl = item.fileUrl else { return }
        await cacheController?.photoId(for: item.id, item: item, shouldDownload: true)
        guard let image = await cacheController?.photo(for: item.id), let data = image.jpegData(compressionQuality: 0.9) else { return }

        var dataUrl = fileUrl
        dataUrl.convertFile(data, fileExtension: itemController.config.filenameExtension)

        let newFileUrl = try await fileUrlDataController?.createNewFileUrl(fileId: item.id, unconvertedFileUrl: dataUrl, pathExtension: itemController.config.filenameExtension)
        await cacheItemListModel.resetImageCache(itemId: itemId)
        await itemControllable.cacheControllable?.remove(itemId: itemId)
        await reset(fileUrl: newFileUrl, itemId: item.id)
    }
    
    @MainActor func isNotJpegPhoto(itemId: UUID) -> Bool {
        guard let item = editModel(for: itemId) else { return false }
        guard let fileUrl = item.fileUrl else { return false }
        return !(fileUrl.fileExtension == itemController.config.filenameExtension || fileUrl.fileExtension == "jpeg")
    }

    func loadImage(cacheType: CacheItemListModel.CacheType, item: Model, itemId: UUID, fileUrl: FileUrl?, reset: Bool = false) async -> AKImage? {
        guard fileUrl != nil else { return nil }
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
        
    func resetPhoto(image: AKImage?, itemId: UUID) async {
        let data = image?.jpegData(compressionQuality: 0.9)
        try? await resetFile(data: data, itemId: itemId, path: "")
    }
}
