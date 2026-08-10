// @copyright André Trettin

import CoreRPG
import Foundation

#if canImport(PDFKit)
import PDFKit
#endif

struct CacheController: Sendable {
    @MainActor init(fileUrlDataController: FileUrlDataController) {
        self.imageCacheController = ImageCacheController()
        self.thumbnailCacheController = ImageCacheController()
        self.fileUrlDataController = fileUrlDataController
        self.observableImageCache = ObservableImageCache()
    }

    let imageCacheController: ImageCacheController
    let thumbnailCacheController: ImageCacheController
    let fileUrlDataController: FileUrlDataController?
    let observableImageCache: ObservableImageCache
}

extension CacheController: ImageCacheControllable {    
    @MainActor func createThumbnail(for itemId: UUID, item: any ItemDataAccessable) async {
        guard let fileUrlDataController, let fileUrl = item.fileUrl else { return }
        let thumbnail = await fileUrlDataController.url(for: fileUrl) { url -> AKImage? in
            await AKImage.quickLookThumbnail(for: url, size: CGSize(width: 210, height: 297))
        }
        await cacheThumbnail(thumbnail, for: itemId)
    }
}
