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
    var fileUrlDataController: FileUrlDataController { get }

//    func photo(for itemId: UUID) async -> AKImage?
//    func thumbnail(for itemId: UUID) async -> AKImage?
//    func remove(itemId: UUID) async
//    
//    @discardableResult
//    func photoId(for itemId: UUID, with fileUrl: FileUrl?, shouldDownload: Bool) async -> UUID?
//    @discardableResult
//    func thumbnailId(for itemId: UUID, with fileUrl: FileUrl?) async -> UUID?
    
    func createImage(for itemId: UUID, fileUrl: FileUrl?) async
    func createThumbnail(for itemId: UUID, fileUrl: FileUrl?) async
}

extension ImageCacheControllable {
    public func photo(for itemId: UUID) async -> AKImage? {
        let image = await imageCacheController.object(for: itemId)
        image?.resetSize()
        return image
    }
    
    public func thumbnail(for itemId: UUID) async -> AKImage? {
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
                if await fileUrlDataController.hasAccess(for: fileUrl) == false {
                    try? await fileUrlDataController.download(fileUrl: fileUrl)
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
