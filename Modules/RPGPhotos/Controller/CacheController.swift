// @copyright André Trettin

import AndrenalinKit
import Foundation
import os.log

#if os(macOS)
internal import AppKit
#else
internal import UIKit
#endif

struct CacheController: Sendable {
    weak var root: PhotoRoot!
    
    private let imageCacheController: ImageCacheController = ImageCacheController()
    private let thumbnailCacheController: ImageCacheController = ImageCacheController()
    
    func image(for itemId: UUID) async -> AKImage? {
        let image = await imageCacheController.object(for: itemId)
        image?.resetSize()
        return image
    }
    
    func thumbnail(for itemId: UUID) async -> AKImage? {
        await thumbnailCacheController.object(for: itemId)
    }
    
    func remove(itemId: UUID) async {
        await imageCacheController.removeObject(for: itemId)
        await thumbnailCacheController.removeObject(for: itemId)
    }
    
    @discardableResult
    func photoId(for itemId: UUID, with fileUrl: FileUrl?, shouldDownload: Bool = false) async -> UUID? {
        guard let fileUrl else { return nil }
        guard await !imageCacheController.hasObject(for: itemId) else { return itemId }
        let imageTask = Task.detached(priority: .userInitiated) {
            if shouldDownload {
                if await root.fileUrlDataController.hasAccess(for: fileUrl) == false {
                    try? await root.fileUrlDataController.download(fileUrl: fileUrl)
                    await thumbnailCacheController.removeObject(for: itemId)
                }
            }
            await self.createImage(for: itemId, fileUrl: fileUrl)
        }
        _ = await imageTask.value
        return await imageCacheController.hasObject(for: itemId) ? itemId : nil
    }
    
    @discardableResult
    func thumbnailId(for itemId: UUID, with fileUrl: FileUrl?) async -> UUID? {
        guard let fileUrl else { return nil }
        guard await !thumbnailCacheController.hasObject(for: itemId) else { return itemId }
        let imageTask = Task.detached(priority: .userInitiated) {
            await self.createThumbnail(for: itemId, fileUrl: fileUrl)
        }
        _ = await imageTask.value
        return await thumbnailCacheController.hasObject(for: itemId) ? itemId : nil
    }
}

private extension CacheController {
    func createImage(for itemId: UUID, fileUrl: FileUrl?) async {
        guard let fileUrl else { return }
        let image: AKImage?
        if let data = fileUrl.data {
            image = AKImage(data: data)
        } else {
            image = await root.fileUrlDataController.url(for: fileUrl) { url -> AKImage? in
                guard let url else { return nil }
                return AKImage(contentsOfFile: url.relativePath)
            }
        }
        if let image {
            await imageCacheController.setObject(image, for: itemId)
        } else {
            Logger.cacheController.warning("Cannot get image \(itemId, privacy: .public)")
        }
    }

    func createThumbnail(for itemId: UUID, fileUrl: FileUrl?) async {
        let cachedImage = await imageCacheController.object(for: itemId)
        if cachedImage == nil {
            await createImage(for: itemId, fileUrl: fileUrl)
        }
        guard let image = await imageCacheController.object(for: itemId) else { return }
        let thumbnail = image.resize(to: PhotoRoot.thumbnailSize, topAligned: true)
        if let thumbnail {
            await thumbnailCacheController.setObject(thumbnail, for: itemId)
        }
    }
}

