// @copyright André Trettin

import CoreRPG
import Foundation

struct CacheController: Sendable {
    @MainActor init(fileUrlDataController: FileUrlDataController) {
        cacheStorage = ImageCacheControllableStorage(fileUrlDataController: fileUrlDataController)
    }

    let cacheStorage: ImageCacheControllableStorage
}

extension CacheController: ImageCacheControllable {
    /// QuickLook's default 3D-object preview canvas proportions.
    private static let thumbnailSize = CGSize(width: 393, height: 350)

    @MainActor func createThumbnail(for itemId: UUID, item: any ItemDataAccessable) async {
        await createQuickLookThumbnail(for: itemId, item: item, size: Self.thumbnailSize, removeWhiteBackground: true)
    }
}
