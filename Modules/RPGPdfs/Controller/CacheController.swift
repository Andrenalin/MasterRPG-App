// @copyright André Trettin

import AndrenalinKit
import Foundation
import os.log

#if canImport(PDFKit)
import PDFKit
#endif

#if canImport(QuickLookThumbnailing)
import QuickLookThumbnailing
#endif

struct CacheController: Sendable {
    weak var root: PdfRoot!
    
    private let thumbnailCacheController: ImageCacheController = ImageCacheController()
        
    func thumbnail(for itemId: UUID) async -> AKImage? {
        await thumbnailCacheController.object(for: itemId)
    }
    
    func remove(itemId: UUID) async {
        await thumbnailCacheController.removeObject(for: itemId)
    }

    @discardableResult
    func thumbnailId(for itemId: UUID, with fileUrl: FileUrl?, shouldDownload: Bool = false) async -> UUID? {
        guard let fileUrl else { return nil }
        guard await !thumbnailCacheController.hasObject(for: itemId) else { return itemId }
        let imageTask = Task.detached(priority: .userInitiated) {
            if shouldDownload {
                try? await root.fileUrlDataController.download(fileUrl: fileUrl)
            }
            await self.createThumbnail(for: itemId, fileUrl: fileUrl)
        }
        _ = await imageTask.value
        return await thumbnailCacheController.hasObject(for: itemId) ? itemId : nil
    }
}

private extension CacheController {
    private func createThumbnail(for itemId: UUID, fileUrl: FileUrl) async {
        let thumbnail = await root.fileUrlDataController.url(for: fileUrl) { url -> AKImage? in
            guard let url else { return nil }
            return await CacheController.generateThumbnail(for: url)
        }
        if let thumbnail {
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
