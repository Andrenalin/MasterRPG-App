// @copyright André Trettin

import CoreRPG
import Foundation
import Observation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct EditController: Sendable {
    @MainActor init(itemController: ItemController, linkRegisterControllable: LinkRegisterControllable) {
        self.linkRegisterControllable = linkRegisterControllable
        self.itemController = itemController
        self.editorModel = ItemEditorModel()
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
    func convert(itemId: UUID) async throws {
        guard let editModel = await editModel(for: itemId) else  { return }
        await cacheController?.photoId(for: editModel.id, item: editModel, shouldDownload: true)
        guard let image = await cacheController?.photo(for: editModel.id), let data = image.jpegData(compressionQuality: 0.9), let fileUrl = editModel.fileUrl else { return }

        var dataUrl = fileUrl
        dataUrl.convertFile(data, fileExtension: itemController.config.filenameExtension)

        let newFileUrl = try await fileUrlDataController?.createNewFileUrl(fileId: editModel.id, unconvertedFileUrl: dataUrl, pathExtension: itemController.config.filenameExtension)
        await reset(fileUrl: newFileUrl, itemId: editModel.id)
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
    
    @MainActor func isNotJpegPhoto(itemId: UUID) -> Bool {
        guard let editModel = editModel(for: itemId) else  { return false }
        guard let fileUrl = editModel.fileUrl else { return false }
        return !(fileUrl.fileExtension == itemController.config.filenameExtension || fileUrl.fileExtension == "jpeg")
    }
}
