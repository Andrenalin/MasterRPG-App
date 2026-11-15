// @copyright André Trettin

import Foundation
import ImageIO
import UniformTypeIdentifiers

/// How the share extension turns image bytes it was handed into what it stores: bytes ImageIO does
/// not read as an image are refused, a small image passes through, a big one is downsampled. Lives
/// in CoreRPG (the extension cannot be unit-tested) so the rules have tests. See CODE_AUDIT_26 §10.21.
public enum SharedImageDownsampling {
    public enum Failure: Error, Equatable {
        /// Empty, undecodable or over-the-pixel-limit data.
        case notUsableAsImage
    }

    /// Images up to this many bytes are stored as they are.
    public static let maximumRawImageByteSize = 8 * ByteUnit.mebibyte
    /// Longest side of a downsampled image.
    public static let maximumDownsampledPixelDimension: CGFloat = 4_096

    /// A single large photo (ProRAW, HEIC panorama) can on its own exceed the Share Extension's
    /// ~120MB budget. Downsamples via ImageIO's thumbnail generator, which decodes directly at the
    /// target size rather than decoding the source and scaling afterward. Small images pass
    /// through untouched. See CODE_AUDIT §6.3.
    public static func downsampledIfNeeded(
        _ data: Data,
        maximumRawByteSize: Int = maximumRawImageByteSize,
        maximumPixelDimension: CGFloat = maximumDownsampledPixelDimension
    ) throws -> Data {
        // Bytes that ImageIO does not read as an image are not stored as a Photo, however small.
        // See CODE_AUDIT_23 §6.6.
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              ImageDownsampler.declaredSize(of: source) != .overLimits else {
            throw Failure.notUsableAsImage
        }
        guard data.count > maximumRawByteSize else { return data }
        return downsampled(source, maximumPixelDimension: maximumPixelDimension) ?? data
    }

    /// The JPEG of `source` scaled to at most `maximumPixelDimension` on its longest side, or `nil`
    /// when the header declares more pixels than the shared limit (nothing is decoded then) or the
    /// image cannot be written.
    public static func downsampled(
        _ source: CGImageSource,
        maximumPixelDimension: CGFloat = maximumDownsampledPixelDimension
    ) -> Data? {
        guard ImageDownsampler.declaredSize(of: source) != .overLimits,
              let thumbnail = ImageDownsampler.downsampledImage(from: source, maxPixelSize: maximumPixelDimension) else {
            return nil
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(
            destination,
            thumbnail,
            [kCGImageDestinationLossyCompressionQuality: JPEGQuality.downsampledImport] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
