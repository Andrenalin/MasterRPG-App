#if !os(tvOS)

import AndrenalinKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension SpaceEntity {
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
        
        guard let image = isThumbnail ? await root.cacheController?.thumbnail(for: self.id) : await root.cacheController?.photo(for: self.id) else {
            throw ImageCreationError()
        }
        #if canImport(UIKit)
        if let imageData = image.pngData() {
            return imageData
        } else {
            throw ImageCreationError()
        }
        #elseif canImport(AppKit)
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
            throw ImageCreationError()
        }
        return pngData
        #else
        throw ImageCreationError()
        #endif
    }
}

#endif
