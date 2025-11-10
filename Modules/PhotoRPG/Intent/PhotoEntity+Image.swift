// @copyright André Trettin

#if !os(tvOS)
import CoreRPG

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

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
        struct ImageCreationError: Error {}
        guard let image = await root.loadImage(for: self.id, isThumbnail: isThumbnail) else {
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
