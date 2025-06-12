// @copyright André Trettin

import AndrenalinKit
import Foundation
import RPGPhotos
import os.log

#if !os(tvOS)
import QuickLookThumbnailing
#endif

struct CacheController: Sendable {
    weak var root: MapRoot!
    
    private let thumbnailCacheController: ImageCacheController = ImageCacheController()
    
    func thumbnail(for itemId: UUID) async -> AKImage? {
        await thumbnailCacheController.object(for: itemId)
    }
    
    func remove(itemId: UUID) async {
        await thumbnailCacheController.removeObject(for: itemId)
    }
    
    func resetThumbnailEntry(item: MapModel, entryId: UUID) async {
        await remove(itemId: entryId)
        await thumbnailId(for: item, entryId: entryId)
    }
    
    @discardableResult
    func thumbnailId(for item: MapModel, entryId: MapEntryModel.ID) async -> MapEntryModel.ID? {
        guard item.photoId != nil, item[entryId].coordinates.count > 2 else { return nil }
        guard await !thumbnailCacheController.hasObject(for: entryId) else { return entryId }
        let imageTask = Task.detached(priority: .userInitiated) {
            await self.createThumbnail(for: item, entryId: entryId)
        }
        _ = await imageTask.value
        return await thumbnailCacheController.hasObject(for: entryId) ? entryId : nil
    }
}

private extension CacheController {
    func createThumbnail(for item: MapModel, entryId: MapEntryModel.ID) async {
        guard await root.photoRoot.requestImageCache(for: item.photoId) else { return }
        guard !Task.isCancelled else { return }
        guard let result = await root.photoRoot.fetchPhotoImage(for: item.photoId, useGame: false) else { return }
        guard !Task.isCancelled else { return }
        let entry = item[entryId]
        let thumbnail = result.0.cropping(to: entry.rect)
        if let thumbnail {
            await thumbnailCacheController.setObject(thumbnail, for: entryId)
        }
    }
}
