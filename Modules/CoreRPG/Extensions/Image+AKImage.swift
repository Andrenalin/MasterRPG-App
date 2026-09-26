// @copyright André Trettin

import ImageIO
import SwiftUI
import os.log

#if !os(tvOS)
import QuickLookThumbnailing
#endif

#if os(macOS)
import AppKit

public typealias AKImage = NSImage

//extension NSImage: @unchecked @retroactive Sendable {}

public extension Image {
    init(akImage: AKImage) {
        self.init(nsImage: akImage)
    }
}

public extension NSImage {
    func jpegData(compressionQuality: CGFloat) -> Data? {
        guard let tiff = tiffRepresentation else { return nil }
        guard let imageRep = NSBitmapImageRep(data: tiff) else { return nil }
        
        let options: [NSBitmapImageRep.PropertyKey: Any] = [
            .compressionFactor: compressionQuality,
        ]
        
        return imageRep.representation(using: .jpeg, properties: options)
    }

    /// Mirrors `UIImage.pngData()`'s signature so `AKImage.pngRepresentationData()` can call
    /// through uniformly on every platform. See CODE_AUDIT_9 §9.4.
    func pngData() -> Data? {
        guard let tiff = tiffRepresentation else { return nil }
        guard let imageRep = NSBitmapImageRep(data: tiff) else { return nil }
        return imageRep.representation(using: .png, properties: [:])
    }
}

public extension AKImage {
    @concurrent
    func resize(to targetSize: CGSize, topAligned: Bool = false) async -> AKImage? {
        let widthRatio = targetSize.width / size.width
        let heightRatio = targetSize.height / size.height
        
        var sourceRect: CGRect = .zero
        if topAligned {
            if widthRatio > heightRatio {
                let originSrc = CGPoint(x: 0, y: size.height - size.width)
                let sizeSrc = CGSize(width: size.width, height: size.width)
                sourceRect = CGRect(origin: originSrc, size: sizeSrc)
            } else {
                let diff = (size.width - size.height)
                var x = 0.0
                if diff > 1.0 {
                    x = diff / 2.0
                }
                let originSrc = CGPoint(x: x, y: 0.0)
                let sizeSrc = CGSize(width: size.height, height: size.height)
                sourceRect = CGRect(origin: originSrc, size: sizeSrc)
            }
        }
        
        let rect = CGRect(origin: .zero, size: targetSize)
        let newImage = NSImage(size: rect.size)
        newImage.lockFocus()
        let ctx = NSGraphicsContext.current
        ctx?.imageInterpolation = .high
        draw(in: rect, from: sourceRect, operation: .copy, fraction: 1)
        newImage.unlockFocus()
        
        return newImage
    }
    
    var fixedSize: CGSize {
        var width = size.width
        var height = size.height
        representations.forEach {
            width = max(width, CGFloat($0.pixelsWide))
            height = max(height, CGFloat($0.pixelsHigh))
        }
        return CGSize(width: width, height: height)
    }
    
    func resetSize() {
        size = fixedSize
    }
}

#else
import UIKit

public typealias AKImage = UIImage

public extension Image {
    init(akImage: AKImage) {
        self.init(uiImage: akImage)
    }
}

public extension AKImage {
    
    @concurrent
    func resize(to targetSize: CGSize, topAligned: Bool = false) async -> AKImage? {
        let pixelScale: CGFloat = 3.0

        let widthRatio = targetSize.width / size.width
        let heightRatio = targetSize.height / size.height
        let minRatio = min(widthRatio, heightRatio)
        var sourceRect = CGRect(origin: .zero, size: targetSize * pixelScale)
        if topAligned {
            if widthRatio > heightRatio {
                let originSrc = CGPoint.zero
                let sizeSrc = CGSize(width: size.width * widthRatio, height: size.height * widthRatio)
                sourceRect = CGRect(origin: originSrc, size: sizeSrc * pixelScale)
            } else {
                let diff = (size.width - size.height)
                var x = 0.0
                if diff > 1.0 {
                    x = diff / 2.0
                }
                let originSrc = CGPoint(x: -x * minRatio, y: 0.0)
                let sizeSrc = CGSize(width: size.width * heightRatio, height: size.height * heightRatio)
                sourceRect = CGRect(origin: originSrc * pixelScale, size: sizeSrc * pixelScale)
            }
        }
        
        let rect = CGRect(origin: .zero, size: targetSize * pixelScale)
        
        let renderer = UIGraphicsImageRenderer(size: rect.size)
        
        return renderer.image { _ in
            draw(in: sourceRect)
        }
    }
    
    var fixedSize: CGSize {
        size
    }
    
    func resetSize() {
        // nothing to do
    }
}

#endif

public extension AKImage {
    /// A downsampled decode paired with the scale factor relating it back to the
    /// original image's pixel coordinate space, so rects defined against the source
    /// (e.g. a map room's crop rect) can be mapped onto the downsampled result.
    struct DownsampledResult: Sendable {
        public let image: AKImage
        public let scale: CGFloat
    }

    /// Longest edge, in pixels, a full-size image is decoded at. A 16k x 16k battle map would be
    /// roughly a 1 GB bitmap; 8192 keeps it near 256 MB. See CODE_AUDIT_17 §7.6.
    static let maximumDecodedPixelSize: CGFloat = 8192

    /// Decodes at full size but never beyond `maximumDecodedPixelSize`, and forces the bitmap decode
    /// now (on the calling, off-main, context) instead of lazily on first draw on the main thread.
    static func boundedDecode(from data: Data, maxPixelSize: CGFloat = maximumDecodedPixelSize) -> AKImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        return boundedDecode(from: source, maxPixelSize: maxPixelSize)
    }

    /// File-URL variant of `boundedDecode(from:maxPixelSize:)`.
    static func boundedDecode(from url: URL, maxPixelSize: CGFloat = maximumDecodedPixelSize) -> AKImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        return boundedDecode(from: source, maxPixelSize: maxPixelSize)
    }

    private static func boundedDecode(from source: CGImageSource, maxPixelSize: CGFloat) -> AKImage? {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = (properties?[kCGImagePropertyPixelWidth] as? CGFloat) ?? 0
        let height = (properties?[kCGImagePropertyPixelHeight] as? CGFloat) ?? 0
        let longestEdge = max(width, height)
        // Unknown dimensions: let the platform decoder handle it as before.
        guard longestEdge > 0 else { return nil }
        return downsampledThumbnail(from: source, maxPixelSize: min(longestEdge, maxPixelSize))?.image
    }

    /// Decodes a thumbnail straight from image data via ImageIO, downsampling during
    /// decode instead of fully decoding the source at native resolution first.
    static func downsampledThumbnail(from data: Data, maxPixelSize: CGFloat) -> AKImage? {
        downsampledThumbnailWithScale(from: data, maxPixelSize: maxPixelSize)?.image
    }

    /// Decodes a thumbnail straight from a file URL via ImageIO, downsampling during
    /// decode instead of fully decoding the source at native resolution first.
    static func downsampledThumbnail(from url: URL, maxPixelSize: CGFloat) -> AKImage? {
        downsampledThumbnailWithScale(from: url, maxPixelSize: maxPixelSize)?.image
    }

    /// Same as `downsampledThumbnail(from:maxPixelSize:)`, but also reports the scale
    /// between the downsampled result and the original image's pixel dimensions.
    static func downsampledThumbnailWithScale(from data: Data, maxPixelSize: CGFloat) -> DownsampledResult? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        return downsampledThumbnail(from: source, maxPixelSize: maxPixelSize)
    }

    /// Same as `downsampledThumbnail(from:maxPixelSize:)`, but also reports the scale
    /// between the downsampled result and the original image's pixel dimensions.
    static func downsampledThumbnailWithScale(from url: URL, maxPixelSize: CGFloat) -> DownsampledResult? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        return downsampledThumbnail(from: source, maxPixelSize: maxPixelSize)
    }

    private static func downsampledThumbnail(from source: CGImageSource, maxPixelSize: CGFloat) -> DownsampledResult? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let originalWidth = (properties?[kCGImagePropertyPixelWidth] as? CGFloat) ?? CGFloat(cgImage.width)
        let scale = originalWidth > 0 ? CGFloat(cgImage.width) / originalWidth : 1
#if os(macOS)
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
#else
        let image = UIImage(cgImage: cgImage)
#endif
        return DownsampledResult(image: image, scale: scale)
    }
}

public extension AKImage {
    /// Renders a best-effort QuickLook preview thumbnail for a file the platform
    /// has no direct decoder for (PDF, USDZ/3D, …). Shared by PdfRPG's and
    /// SpaceRPG's `CacheController`s, which previously each defined an
    /// identical wrapper around `QLThumbnailGenerator`.
    static func quickLookThumbnail(
        for url: URL?,
        size: CGSize,
        scale: CGFloat = 2,
        removeWhiteBackground: Bool = false
    ) async -> AKImage? {
        guard let url else { return nil }
#if !os(tvOS)
        let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: scale, representationTypes: .all)
        let generator = QLThumbnailGenerator.shared
        do {
            let result = try await generator.generateBestRepresentation(for: request)
#if os(macOS)
            return result.nsImage
#else
            let image = result.uiImage
            return removeWhiteBackground ? image.removeWhiteBackground() : image
#endif
        } catch let error {
            Logger.cacheController.error("QLThumbnail failed \(error.localizedDescription, privacy: .public)")
        }
#endif
        return nil
    }
}

/// Thrown by `AKImage.pngRepresentationData()` when PNG encoding fails.
public struct AKImageEncodingError: Error, Sendable {
    public init() {}
}

public extension AKImage {
    /// Cross-platform PNG encode, throwing instead of returning an optional so AppIntent
    /// `Entity` conformances (`PdfEntity`, `PhotoEntity`, `SpaceEntity`) don't each need their
    /// own local error type and `#if canImport(UIKit)/#elseif canImport(AppKit)` branch — the
    /// platform difference (`UIImage.pngData()` is native; `NSImage.pngData()` is the bridge
    /// extension above) is resolved once, here. See CODE_AUDIT_9 §9.4.
    func pngRepresentationData() throws -> Data {
        guard let data = pngData() else {
            throw AKImageEncodingError()
        }
        return data
    }
}

/// Named JPEG compression-quality tiers, so each `jpegData(compressionQuality:)`
/// call site documents the tradeoff it's making instead of a bare, unexplained
/// float. The values already in use across the app genuinely serve different
/// purposes — this doesn't unify them to one number, only names the ones that exist.
public enum JPEGQuality {
    /// Bandwidth-constrained real-time transport (e.g. mirroring a game screen
    /// over the network), where small size matters more than fidelity.
    public static let transport: CGFloat = 0.5
    /// Disk-cached thumbnails — balances file size against visible quality.
    public static let cachedThumbnail: CGFloat = 0.8
    /// A user-provided import clamped down to a bounded pixel size before it enters
    /// the app's working copy (e.g. `ItemProviderImporter.downsampledIfNeeded`) —
    /// higher fidelity than a thumbnail since it may still be viewed at near-full
    /// size, but not the export tier since the source was already downsampled.
    public static let downsampledImport: CGFloat = 0.85
    /// User-facing exports/edits, where fidelity matters more than size.
    public static let export: CGFloat = 0.9
}
