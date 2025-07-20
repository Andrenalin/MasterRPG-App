import CoreRPG

#if canImport(UIKit)
internal import UIKit
#elseif canImport(AppKit)
internal import AppKit
#endif

@available(iOS 26.0, macOS 26.0, tvOS 26.0, visionOS 26.0, *)
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
