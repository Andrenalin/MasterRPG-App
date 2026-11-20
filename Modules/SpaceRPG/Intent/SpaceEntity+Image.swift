// @copyright André Trettin

#if !os(tvOS)
import CoreRPG
import Foundation

extension SpaceEntity {
    /// The 3D object's thumbnail: the module renders QuickLook thumbnails only, so the full-image
    /// cache is always empty. See CODE_AUDIT §5.9.
    var imageRepresentationData: Data {
        get async throws {
            try await loadAssetData()
        }
    }

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
