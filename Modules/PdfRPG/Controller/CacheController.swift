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

extension CacheController: QuickLookThumbnailProviding {
    /// A4 portrait proportions — most PDFs are page-shaped, and QuickLook
    /// preserves aspect ratio regardless, so this is just a generous bound.
    public static let quickLookThumbnailSize = CGSize(width: 210, height: 297)
}
