// @copyright André Trettin

#if !os(tvOS)

import CoreRPG
import Foundation

extension SpaceEntity {
    /// The thumbnail, through the helper the Pdf and Space entities share. See CODE_AUDIT_29 §9.3.
    var imageRepresentationData: Data {
        get async throws {
            try await root.itemController.exportedThumbnailPngData(itemId: id, cacheController: root.cacheController)
        }
    }
}

#endif
