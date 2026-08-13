// @copyright André Trettin

import CoreRPG
import Foundation

#if canImport(PDFKit)
import PDFKit
#endif

struct CacheController: Sendable {
    @MainActor init(fileUrlDataController: FileUrlDataController) {
        cacheStorage = ImageCacheControllableStorage(fileUrlDataController: fileUrlDataController)
    }

    let cacheStorage: ImageCacheControllableStorage
}

extension CacheController: ImageCacheControllable {
    /// A4 portrait proportions — most PDFs are page-shaped, and QuickLook
    /// preserves aspect ratio regardless, so this is just a generous bound.
    private static let thumbnailSize = CGSize(width: 210, height: 297)

    @MainActor func createThumbnail(for itemId: UUID, item: any ItemDataAccessable) async {
        guard let fileUrlDataController, let fileUrl = item.fileUrl else { return }
        let thumbnail = await fileUrlDataController.url(for: fileUrl) { url -> AKImage? in
            await AKImage.quickLookThumbnail(for: url, size: Self.thumbnailSize)
        }
        await cacheThumbnail(thumbnail, for: itemId)
    }
}
