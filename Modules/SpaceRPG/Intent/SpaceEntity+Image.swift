// @copyright André Trettin

#if !os(tvOS)
import CoreRPG
import Foundation

extension SpaceEntity {
    var imageRepresentationData: Data {
        get async throws {
            guard let image = await root.cacheController?.photo(for: self.id) else {
                throw AKImageEncodingError()
            }
            return try image.pngRepresentationData()
        }
    }
}

#endif
