// @copyright André Trettin

import CoreGraphics
import CoreRPG
import Foundation
import PhotoRPG
import os.log

#if !os(tvOS)
import QuickLookThumbnailing
#endif

struct CacheController: Sendable {
    @MainActor init(photoRoot: PhotoRootModel) {
        self.photoRoot = photoRoot
        cacheStorage = ImageCacheControllableStorage()
    }

    let photoRoot: PhotoRootModel

    let cacheStorage: ImageCacheControllableStorage
}

extension CacheController: ImageCacheControllable {
    /// ImageIO thumbnail max pixel size: large enough that even a small room crop
    /// keeps reasonable detail, while still skipping a full-resolution map decode.
    private static let thumbnailMaxPixelSize: CGFloat = 1024

    @MainActor func createThumbnail(for itemId: UUID, item: any ItemDataAccessible) async {
        guard let item = item as? MapModel else { return }
        guard !Task.isCancelled else { return }
        guard let source = await photoRoot.fetchPhotoThumbnailSource(
            for: item.photoId,
            maxPixelSize: Self.thumbnailMaxPixelSize
        ) else { return }
        guard !Task.isCancelled else { return }
        let entry = item[itemId]
        let scaledRect = entry.rect.applying(CGAffineTransform(scaleX: source.scale, y: source.scale))
        let thumbnail = source.image.cropping(to: scaledRect)
        await cacheThumbnail(thumbnail, for: itemId)
    }
}

