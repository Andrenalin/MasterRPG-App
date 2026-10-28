// @copyright André Trettin

import CoreRPG
import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The shared `GenericEditController`; the photo behaviour below needs no stored state of its
/// own. See CODE_AUDIT_Folder §9.3.
typealias EditController = GenericEditController<PhotoModel>

extension EditController {
    var cacheController: CacheController? { itemControllable.cacheControllable as? CacheController }
}

extension EditController {
    @MainActor func convert(itemId: UUID) async throws {
        guard let item = editModel(for: itemId), let fileUrl = item.fileUrl else { return }
        await cacheController?.photoId(for: item.id, item: item, shouldDownload: true)
        guard let image = await cacheController?.photo(for: item.id), let data = image.jpegData(compressionQuality: JPEGQuality.export) else { return }

        var dataUrl = fileUrl
        dataUrl.convertFile(data, fileExtension: itemControllable.config.filenameExtension)

        let newFileUrl = try await fileUrlDataController?.createNewFileUrl(fileId: item.id, unconvertedFileUrl: dataUrl, pathExtension: itemControllable.config.filenameExtension)
        await itemControllable.cacheControllable?.remove(itemId: itemId)
        reset(fileUrl: newFileUrl, itemId: item.id)
    }
    
    @MainActor func isNotJpegPhoto(itemId: UUID) -> Bool {
        guard let item = editModel(for: itemId) else { return false }
        guard let fileUrl = item.fileUrl else { return false }
        return !(fileUrl.fileExtension == itemControllable.config.filenameExtension || fileUrl.fileExtension == "jpeg")
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
        
    func resetPhoto(image: AKImage?, itemId: UUID, replaced: ReplacedFileDisposal = .delete) async throws {
#if os(macOS)
        let data = image?.jpegData(compressionQuality: JPEGQuality.export)
#else
        // Encoded off the main actor: a 48 MP camera photo hitched the UI.
        // See CODE_AUDIT_21 §7.10.
        let data = await Self.encodedJPEG(image)
#endif
        try await resetFile(data: data, itemId: itemId, path: "", replaced: replaced)
    }

    /// Stores the picked or dropped image `data` as the item's photo. Returns `false` when the
    /// data is no image. Decoding and encoding run off the main actor, and the image is decoded
    /// at most at the size the app shows images at; the library and drop paths used to decode
    /// and re-encode at full resolution on the main actor. See CODE_AUDIT_21 §7.10.
    func resetPhoto(data: Data, itemId: UUID, replaced: ReplacedFileDisposal = .delete, forceSave: Bool = false) async throws -> Bool {
        guard let jpeg = await Self.importedJPEG(from: data) else { return false }
        try await resetFile(data: jpeg, itemId: itemId, path: "", replaced: replaced, forceSave: forceSave)
        return true
    }

    @concurrent
    private static func importedJPEG(from data: Data) async -> Data? {
        (AKImage.boundedDecode(from: data) ?? AKImage(data: data))?
            .jpegData(compressionQuality: JPEGQuality.export)
    }

#if !os(macOS)
    @concurrent
    private static func encodedJPEG(_ image: AKImage?) async -> Data? {
        image?.jpegData(compressionQuality: JPEGQuality.export)
    }
#endif
}
