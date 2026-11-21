// @copyright André Trettin

import CoreRPG
import CoreGraphics
import Foundation
import ImageIO

/// Produces the cutout of a photo's subject that the 3D table stands on a pin's base.
struct PinCutoutController: Sendable {
    let fileUrlDataController: FileUrlDataController

    /// - Returns: the subject with a transparent background, or `nil` when the photo has no
    ///   usable subject or cannot be read. The caller keeps its flat photo token in that case.
    @MainActor
    func cutout(photoId: UUID, item: any ItemDataAccessible) async -> CGImage? {
        guard let fileUrl = item.fileUrl else { return nil }
        let key = PinCutoutKey(photoId: photoId, fileId: fileUrl.fileId, contentHash: fileUrl.contentHash)
        let controller = fileUrlDataController
        return await PinCutoutCache.shared.cutout(for: key) {
            await controller.resolvedImage(
                for: fileUrl,
                decodeData: { Self.downsampled(from: $0) },
                decodeUrl: { Self.downsampled(from: $0) }
            )
        }
    }

    private static func downsampled(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return ImageDownsampler.downsampledImage(from: source, maxPixelSize: PinCutoutPolicy.sourceMaxPixelSize)
    }

    private static func downsampled(from url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return ImageDownsampler.downsampledImage(from: source, maxPixelSize: PinCutoutPolicy.sourceMaxPixelSize)
    }
}

extension PhotoRootModel {
    /// The cutout of the subject of the photo `photoId`, for the 3D table's pin standees.
    @MainActor
    public func pinCutout(for photoId: UUID, item: any ItemDataAccessible) async -> CGImage? {
        guard let fileUrlDataController else { return nil }
        return await PinCutoutController(fileUrlDataController: fileUrlDataController).cutout(photoId: photoId, item: item)
    }
}
