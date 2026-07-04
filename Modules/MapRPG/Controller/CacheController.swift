// @copyright André Trettin

import CoreRPG
import Foundation
import PhotoRPG
import os.log

#if !os(tvOS)
import QuickLookThumbnailing
#endif

actor MapEntryCacheImageMapper {
    var entryToItem: [UUID: UUID] = [:]
}

struct CacheController: Sendable {
    @MainActor init(photoRoot: PhotoRootModel) {
        self.photoRoot = photoRoot
        
        self.imageCacheController = ImageCacheController()
        self.thumbnailCacheController = ImageCacheController()
        self.fileUrlDataController = nil
        self.observableImageCache = ObservableImageCache()
    }
    
    let photoRoot: PhotoRootModel
    
    let imageCacheController: ImageCacheController
    let thumbnailCacheController: ImageCacheController
    let fileUrlDataController: FileUrlDataController?
    let observableImageCache: ObservableImageCache
}

extension CacheController: ImageCacheControllable {
    @MainActor func createThumbnail(for itemId: UUID, item: any ItemDataAccessable) async {
        guard let item = item as? MapModel, await photoRoot.requestImageCache(for: item.photoId) else { return }
        guard !Task.isCancelled else { return }
        guard let result = await photoRoot.fetchPhotoImage(for: item.photoId, useGame: false) else { return }
        guard !Task.isCancelled else { return }
        let entry = item[itemId]
        let thumbnail = result.0.cropping(to: entry.rect)
        if let thumbnail {
            await thumbnailCacheController.saveToDisk(thumbnail, for: itemId)

            await thumbnailCacheController.setObject(thumbnail, for: itemId)
        }
    }
}

