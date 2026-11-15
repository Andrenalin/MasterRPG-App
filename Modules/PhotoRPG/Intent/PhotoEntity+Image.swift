// @copyright André Trettin

#if !os(tvOS)
import CoreRPG
import Foundation

extension PhotoEntity {
    /// The stored photo file's bytes as they are. The image is not decoded and PNG-encoded on
    /// demand: that rebuilt a large photo as a (much larger) PNG just to hand it over, and the
    /// file representation already exports the same bytes. See CODE_AUDIT_26 §7.63.
    var imageRepresentationData: Data {
        get async throws {
            try await loadAssetData()
        }
    }

    private func loadAssetData() async throws -> Data {
        guard let url = await root.itemController.loadableUrl(itemId: id) else {
            throw PhotoEntityAssetUnavailableError()
        }
        return try await Self.readFile(at: url)
    }

    @concurrent
    private static func readFile(at url: URL) async throws -> Data {
        try Data(contentsOf: url, options: .mappedIfSafe)
    }
}

#endif
