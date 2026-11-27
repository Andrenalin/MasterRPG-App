// @copyright André Trettin

#if os(iOS) || os(macOS) || os(visionOS)
import CoreRPG
import Foundation
import MapRPG
import RealityKit
import SwiftUI

#if os(macOS)
import AppKit
/// Internal: `PinPawn.swift` and `RoomHitArea.swift` use it too. See CODE_AUDIT_29 §9.9.
typealias GameTablePlatformColor = NSColor
#else
import UIKit
typealias GameTablePlatformColor = UIColor
#endif

/// Converts a game-table image to `CGImage` across every platform's `AKImage`
/// type (`UIImage` on iOS/visionOS, `NSImage` on macOS). Shared by `PinPawn`
/// and `BoardTextureInput` rather than duplicated.
enum GameTableImage {
    /// Upper bound of the long side, in pixels, of a re-rendered bitmap.
    private static let maximumBitmapDimension: CGFloat = 4_096

    /// The last converted board photo. Fog toggles and room edits rebuild the board texture for
    /// the same photo; the orientation bake / bitmap conversion ran each time. Identity of the
    /// source image is the key (the model keeps the same instance while the photo is current).
    /// See CODE_AUDIT_26 §7.47.
    @MainActor private static var cachedBoardImage: (source: AKImage, converted: CGImage)?

    @MainActor
    static func cachedCGImage(from image: AKImage) -> CGImage? {
        if let cached = cachedBoardImage, cached.source === image { return cached.converted }
        guard let converted = cgImage(from: image) else { return nil }
        cachedBoardImage = (image, converted)
        return converted
    }

    @MainActor
    static func clearBoardImageCache() {
        cachedBoardImage = nil
    }

    static func cgImage(from image: AKImage) -> CGImage? {
#if os(macOS)
        // `NSImage.cgImage(forProposedRect:)` can hand back the rep's raw bitmap without its EXIF
        // orientation, while `size` is the oriented size. Drawing the `NSImage` itself lets AppKit
        // apply the orientation, exactly like it does on screen; the bitmap is capped to keep huge
        // photos affordable.
        let orientedSize = image.size
        guard orientedSize.width > 0, orientedSize.height > 0 else { return nil }
        let pixelLongSide = image.representations
            .map { CGFloat(max($0.pixelsWide, $0.pixelsHigh)) }
            .max() ?? max(orientedSize.width, orientedSize.height)
        let longSide = min(max(1, pixelLongSide), maximumBitmapDimension)
        let scale = longSide / max(orientedSize.width, orientedSize.height)
        let width = max(1, Int((orientedSize.width * scale).rounded()))
        let height = max(1, Int((orientedSize.height * scale).rounded()))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(
            in: NSRect(x: 0, y: 0, width: width, height: height),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
#else
        // `UIImage.cgImage` is the raw bitmap without the EXIF orientation, while `size` (which the
        // board and the map's stored size use) is the oriented size. A sideways-stored photo — common
        // for high-resolution camera images — would otherwise render rotated and letterboxed, so
        // bake the orientation in.
        guard image.imageOrientation != .up else { return image.cgImage }
        let format = UIGraphicsImageRendererFormat.preferred()
        // Capped like the macOS bitmap: an oriented camera photo of 100+ megapixels would
        // otherwise be baked at full size. See CODE_AUDIT_26 §7.46.
        let pixelLongSide = max(image.size.width, image.size.height) * image.scale
        format.scale = pixelLongSide > maximumBitmapDimension
            ? image.scale * maximumBitmapDimension / pixelLongSide
            : image.scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: image.size, format: format)
            .image { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }
            .cgImage
#endif
    }
}

/// Identifies a pin token entity for gesture targeting.
struct PinComponent: Component {
    let pinId: UUID
}

/// Identifies a room's fog hit-test volume for gesture targeting.
struct RoomComponent: Component {
    let roomId: UUID
}


#endif
