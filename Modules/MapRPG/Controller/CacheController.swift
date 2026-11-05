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
        // No coordinates, no area: the crop would be the map's top-left corner.
        guard !entry.coordinates.isEmpty else { return }
        let scaledRect = entry.thumbnailRect.applying(CGAffineTransform(scaleX: source.scale, y: source.scale))
        // Room rects live on the map canvas, which shows the photo rotated by its degrees.
        guard let canvasImage = source.image.rotated(byDegrees: source.degrees) else { return }
        let thumbnail = canvasImage.cropping(to: scaledRect)
        await cacheThumbnail(thumbnail, for: itemId)
    }
}

