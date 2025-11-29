// @copyright André Trettin

import CoreRPG
import Foundation
import os.log

#if canImport(PDFKit)
import PDFKit
#endif

#if !os(tvOS)
import QuickLookThumbnailing
#endif

struct CacheController: Sendable {
    init(fileUrlDataController: FileUrlDataController) {
        self.imageCacheController = ImageCacheController()
        self.thumbnailCacheController = ImageCacheController()
        self.fileUrlDataController = fileUrlDataController
    }
    
    let imageCacheController: ImageCacheController
    let thumbnailCacheController: ImageCacheController
    let fileUrlDataController: FileUrlDataController?
}

extension CacheController: ImageCacheControllable {    
    func createThumbnail(for itemId: UUID, item: any ItemDataAccessable) async {
        guard let fileUrlDataController, let fileUrl = item.fileUrl else { return }
        let thumbnail = await fileUrlDataController.url(for: fileUrl) { url -> AKImage? in
            guard let url else { return nil }
            return await CacheController.generateThumbnail(for: url)
        }
        if let thumbnail {
            await thumbnailCacheController.saveToDisk(thumbnail, for: itemId)
            await thumbnailCacheController.setObject(thumbnail, for: itemId)
        }
    }
    
    static func generateThumbnail(for url: URL?) async -> AKImage? {
        guard let url else { return nil }
        let size = CGSize(width: 210, height: 297)
        let scale: CGFloat = 2

#if !os(tvOS)
        let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: scale, representationTypes: .all)
        let generator = QLThumbnailGenerator.shared
        do {
            let result = try await generator.generateBestRepresentation(for: request)
#if os(macOS)
            return result.nsImage
#else
            return result.uiImage
#endif
        } catch let error {
            Logger.cacheController.error("QLThumbnail failed \(error.localizedDescription, privacy: .public)")
        }
#endif
        return nil
    }
}
