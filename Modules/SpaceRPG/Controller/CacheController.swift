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
    @MainActor func createThumbnail(for itemId: UUID, item: any ItemDataAccessable) async {
        guard let fileUrlDataController, let fileUrl = item.fileUrl else { return }
        let thumbnail = await fileUrlDataController.url(for: fileUrl) { url -> AKImage? in
            await AKImage.quickLookThumbnail(
                for: url,
                size: CGSize(width: 393, height: 350),
                removeWhiteBackground: true
            )
        }
        await cacheThumbnail(thumbnail, for: itemId)
    }
}
