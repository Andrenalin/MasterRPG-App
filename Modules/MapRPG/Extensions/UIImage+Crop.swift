// @copyright André Trettin

import CoreGraphics
import CoreRPG

/// Redraws `image` rotated clockwise by `degrees` into the bounding box of the rotated bitmap, the
/// transform SwiftUI's `rotationEffect` applies to a map photo. The corners outside the photo stay clear.
private func rotatedCGImage(_ image: CGImage, degrees: Double) -> CGImage? {
    let size = ViewportGeometry.rotatedContentSize(
        CGSize(width: image.width, height: image.height),
        rotationDegrees: degrees
    )
    let width = Int(size.width.rounded())
    let height = Int(size.height.rounded())
    guard width > 0, height > 0,
          let context = CGContext(
              data: nil,
              width: width,
              height: height,
              bitsPerComponent: 8,
              bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ) else { return nil }
    context.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
    // Core Graphics is y-up, so a clockwise rotation on screen is a negative angle.
    context.rotate(by: -degrees * .pi / 180)
    context.draw(
        image,
        in: CGRect(x: -CGFloat(image.width) / 2, y: -CGFloat(image.height) / 2, width: CGFloat(image.width), height: CGFloat(image.height))
    )
    return context.makeImage()
}

/// `rect` (canvas coordinates, top-left origin) of `image` rotated clockwise by `degrees`, drawn
/// directly into a bitmap of the size of the crop. The former path redrew the whole rotated
/// bitmap first, even for a 3 x 3 px room, once per room. A multiple of 360 degrees crops without
/// any drawing. `nil` when the rotation fails or `rect` lies outside the canvas.
/// See CODE_AUDIT_26 §7.14.
func rotatedCroppedCGImage(_ image: CGImage, degrees: Double, to rect: CGRect) -> CGImage? {
    guard degrees.truncatingRemainder(dividingBy: 360) != 0 else { return image.cropping(to: rect) }
    let size = ViewportGeometry.rotatedContentSize(
        CGSize(width: image.width, height: image.height),
        rotationDegrees: degrees
    )
    let width = Int(size.width.rounded())
    let height = Int(size.height.rounded())
    guard width > 0, height > 0 else { return nil }
    let target = rect.integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
    guard !target.isNull, target.width >= 1, target.height >= 1,
          let context = CGContext(
              data: nil,
              width: Int(target.width),
              height: Int(target.height),
              bitsPerComponent: 8,
              bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ) else { return nil }
    // The crop's pixel (0, 0) is the canvas point (target.minX, target.minY); the context is y-up
    // and the canvas y-down, hence the vertical offset by the canvas height.
    context.translateBy(x: -target.minX, y: target.maxY - CGFloat(height))
    context.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
    context.rotate(by: -degrees * .pi / 180)
    context.draw(
        image,
        in: CGRect(x: -CGFloat(image.width) / 2, y: -CGFloat(image.height) / 2, width: CGFloat(image.width), height: CGFloat(image.height))
    )
    return context.makeImage()
}

#if os(macOS)
import AppKit

extension AKImage {
    /// The bitmap of the image, for work that runs away from the main actor.
    var croppingSourceCGImage: CGImage? {
        var imageRect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        return cgImage(forProposedRect: &imageRect, context: nil, hints: nil)
    }

    static func make(cgImage: CGImage) -> AKImage {
        AKImage(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height))
    }

    func cropping(to rect: CGRect) -> AKImage? {
        var imageRect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        guard let imageRef = cgImage(forProposedRect: &imageRect, context: nil, hints: nil) else { return nil }
        guard let cgImage = imageRef.cropping(to: rect) else { return nil }
        return AKImage(cgImage: cgImage, size: rect.size)
    }

    func rotated(byDegrees degrees: Double) -> AKImage? {
        guard degrees.truncatingRemainder(dividingBy: 360) != 0 else { return self }
        var imageRect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        guard let imageRef = cgImage(forProposedRect: &imageRect, context: nil, hints: nil),
              let rotated = rotatedCGImage(imageRef, degrees: degrees) else { return nil }
        return AKImage(cgImage: rotated, size: CGSize(width: rotated.width, height: rotated.height))
    }
}

#else
import UIKit

extension AKImage {
    var croppingSourceCGImage: CGImage? { cgImage }

    static func make(cgImage: CGImage) -> AKImage { AKImage(cgImage: cgImage) }

    func cropping(to rect: CGRect) -> AKImage? {
        guard let cgImage = cgImage?.cropping(to: rect) else {
            return nil
        }
        return AKImage(cgImage: cgImage)
    }

    func rotated(byDegrees degrees: Double) -> AKImage? {
        guard degrees.truncatingRemainder(dividingBy: 360) != 0 else { return self }
        guard let cgImage, let rotated = rotatedCGImage(cgImage, degrees: degrees) else { return nil }
        return AKImage(cgImage: rotated)
    }
}
#endif

/// The cover tile of a map: a piece of the map canvas, which shows the photo rotated by its degrees.
/// See CODE_AUDIT_26 §5.24.
enum MapTileImage {
    /// `rect` (canvas coordinates) cut out of `image` rotated by `degrees`; `nil` when the rotation
    /// fails or `rect` lies outside the canvas.
    static func crop(_ image: AKImage, degrees: Double, to rect: CGRect) -> AKImage? {
        guard let source = image.croppingSourceCGImage,
              let cropped = rotatedCroppedCGImage(source, degrees: degrees, to: rect) else { return nil }
        return AKImage.make(cgImage: cropped)
    }
}
