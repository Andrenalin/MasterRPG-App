#if !os(tvOS)

import CoreRPG

#if canImport(UIKit)
internal import UIKit
#elseif canImport(AppKit)
internal import AppKit
#endif

extension DiceEntity {
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
        struct ImageCreationError: Error {}
        throw ImageCreationError()
    }
}

#endif
