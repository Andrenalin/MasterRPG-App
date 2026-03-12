// @copyright André Trettin

import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

public protocol ImageCacheControllable: Sendable {
    var imageCacheController: ImageCacheController { get }
    var thumbnailCacheController: ImageCacheController { get }
    var fileUrlDataController: FileUrlDataController? { get }

    func createImage(for itemId: UUID, item: any ItemDataAccessable) async
    func createThumbnail(for itemId: UUID, item: any ItemDataAccessable) async
}

extension ImageCacheControllable {
    public func createImage(for itemId: UUID, item: any ItemDataAccessable) async {}
    
    public func photo(for itemId: UUID) async -> AKImage? {
        let image = await imageCacheController.object(for: itemId)
        image?.resetSize()
        return image
    }
    
    public func thumbnail(for itemId: UUID) async -> AKImage? {
        guard let image = await thumbnailCacheController.object(for: itemId) else {
            guard let fileImage = await thumbnailCacheController.loadFromDisk(for: itemId) else {
                return nil
            }
            await thumbnailCacheController.setObject(fileImage, for: itemId)
            return fileImage
        }
        return image
    }
    
    public func remove(itemId: UUID, includeImage: Bool = true) async {
        if includeImage {
            await imageCacheController.removeObject(for: itemId)
        }
        await thumbnailCacheController.removeObject(for: itemId)
    }
    
    @discardableResult
    public func photoId(for itemId: UUID, item: any ItemDataAccessable, shouldDownload: Bool = false) async -> UUID? {
        guard let fileUrlDataController, let fileUrl = item.fileUrl else { return nil }
        guard await !imageCacheController.hasObject(for: itemId) else { return itemId }
        let imageTask = Task(priority: .userInitiated) {
            if shouldDownload {
                if await fileUrlDataController.hasAccess(for: fileUrl) == false {
                    try? await fileUrlDataController.download(fileUrl: fileUrl)
                    await thumbnailCacheController.removeObject(for: itemId)
                }
            }
            await self.createImage(for: itemId, item: item)
        }
        _ = await imageTask.value
        return await imageCacheController.hasObject(for: itemId) ? itemId : nil
    }
        
    @discardableResult
    public func thumbnailId(for itemId: UUID, item: any ItemDataAccessable) async -> UUID? {
        guard await !thumbnailCacheController.hasObject(for: itemId) else { return itemId }
        let _ = await thumbnail(for: itemId) // load from disk
        guard await !thumbnailCacheController.hasObject(for: itemId) else { return itemId }
        let imageTask = Task(priority: .userInitiated) {
            await self.createThumbnail(for: itemId, item: item)
        }
        _ = await imageTask.value
        return await thumbnailCacheController.hasObject(for: itemId) ? itemId : nil
    }
}
