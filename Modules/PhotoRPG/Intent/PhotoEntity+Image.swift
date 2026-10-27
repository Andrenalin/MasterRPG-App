// @copyright André Trettin

#if !os(tvOS)
import CoreRPG
import Foundation

extension PhotoEntity {
    var imageRepresentationData: Data {
        get async throws {
            try await loadAssetData()
        }
    }

    private func loadAssetData() async throws -> Data {
        guard let image = await root.cacheController?.photo(for: self.id) else {
            throw AKImageEncodingError()
        }
        return try image.pngRepresentationData()
    }
}

#endif
