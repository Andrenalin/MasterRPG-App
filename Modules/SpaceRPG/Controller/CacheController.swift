// @copyright André Trettin

import AndrenalinKit
import Foundation
import os.log

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
    let fileUrlDataController: FileUrlDataController
}

extension CacheController: ImageCacheControllable {
    func createImage(for itemId: UUID, fileUrl: FileUrl?) async {
        //await createThumbnail(for: itemId, fileUrl: fileUrl)
    }

    func createThumbnail(for itemId: UUID, fileUrl: FileUrl?) async {
        guard let fileUrl else { return }
        let thumbnail = await fileUrlDataController.url(for: fileUrl) { url -> AKImage? in
            guard let url else { return nil }
            return await CacheController.generateThumbnail(for: url)
        }
        if let thumbnail {
            await thumbnailCacheController.setObject(thumbnail, for: itemId)
        }
    }
    
    static func generateThumbnail(for url: URL?) async -> AKImage? {
        guard let url else { return nil }
        let size = CGSize(width: 393, height: 350)
        let scale: CGFloat = 2
        
#if !os(tvOS)
        let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: scale, representationTypes: .all)
        let generator = QLThumbnailGenerator.shared
        do {
            let result = try await generator.generateBestRepresentation(for: request)
#if os(macOS)
            return result.nsImage
#else
            return result.uiImage.removeWhiteBackground()
#endif
        } catch let error {
            Logger.cacheController.error("QLThumbnail failed \(error.localizedDescription, privacy: .public)")
        }
#endif
        return nil
    }
}
