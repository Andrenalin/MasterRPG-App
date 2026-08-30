// @copyright André Trettin

#if !os(tvOS)
import CoreRPG
import Foundation

extension PhotoEntity {
    var imageRepresentationData: Data {
        get async throws {
            try await loadAssetData(isThumbnail: false)
        }
    }

    var thumbnailRepresentationData: Data {
        get async throws {
            try await loadAssetData(isThumbnail: true)
        }
    }

    private func loadAssetData(isThumbnail: Bool) async throws -> Data {
        guard let image = isThumbnail ? await root.cacheController?.thumbnail(for: self.id) : await root.cacheController?.photo(for: self.id) else {
            throw AKImageEncodingError()
        }
        return try image.pngRepresentationData()
    }
}

#endif
