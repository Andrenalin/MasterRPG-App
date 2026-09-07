// @copyright André Trettin

import CoreRPG
import Foundation

struct CacheController: Sendable {
    @MainActor init(fileUrlDataController: FileUrlDataController) {
        cacheStorage = ImageCacheControllableStorage(fileUrlDataController: fileUrlDataController)
    }

    let cacheStorage: ImageCacheControllableStorage
}

extension CacheController: QuickLookThumbnailProviding {
    /// QuickLook's default 3D-object preview canvas proportions.
    public static let quickLookThumbnailSize = CGSize(width: 393, height: 350)
    public static let removesWhiteBackgroundInThumbnail = true
}
