#if !os(tvOS)

import CoreRPG
import Foundation

extension PdfEntity {
    var imageRepresentationData: Data {
        get async throws {
            try await loadAssetData()
        }
    }

    /// The PDF's thumbnail: the module renders QuickLook thumbnails only, so the full-image
    /// cache is always empty. See CODE_AUDIT §5.9.
    @MainActor
    private func loadAssetData() async throws -> Data {
        guard let cacheController = root.cacheController,
              let model = root.itemController.itemSync(for: id) else {
            throw AKImageEncodingError()
        }
        return try await cacheController.thumbnailPngData(for: id, item: model)
    }
}

#endif
