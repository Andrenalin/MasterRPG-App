// @copyright André Trettin

#if os(visionOS)
import CoreGraphics
import CoreText
import Foundation
import RealityKit
import Spatial
import UIKit
import simd

/// What the dice generated in code (`Die8`, `Die10`) have in common.
enum GeneratedDie {
    /// The edge of a cell of a die's texture atlas, in pixels. Every color of every die kind keeps
    /// an atlas (RGBA, with mipmaps) in memory, so this is what the dice's texture memory scales
    /// with, by its square: 256 instead of 512 is a quarter of it. The d4 draws three numerals in
    /// each of its few large cells and uses twice this.
    static let atlasCell = 256

    /// The material of a die before its color's texture is ready, and the base of every color's.
    @MainActor
    static func placeholderMaterial() -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: .white)
        material.roughness = .init(floatLiteral: 0.35)
        material.metallic = .init(floatLiteral: 0)
        material.clearcoat = .init(floatLiteral: 0.5)
        material.clearcoatRoughness = .init(floatLiteral: 0.2)
        return material
    }

    /// The orientation that turns this direction — a face's outward normal, or a corner — up.
    static func faceUpOrientation(normal: SIMD3<Float>) -> Rotation3D {
        let up = SIMD3<Float>(0, 1, 0)
        let cosine = min(max(dot(normal, up), -1), 1)
        let rotationAxis = cross(normal, up)
        let axisLength = length(rotationAxis)
        guard axisLength > 0.000_001 else {
            return cosine > 0
                ? .init()
                : .init(angle: .init(degrees: 180), axis: .init(x: 1, y: 0, z: 0))
        }
        let axis = rotationAxis / axisLength
        return .init(
            angle: .init(radians: acos(Double(cosine))),
            axis: .init(x: Double(axis.x), y: Double(axis.y), z: Double(axis.z))
        )
    }

    static func cgColor(_ rgb: TableDiePalette.RGB) -> CGColor {
        CGColor(srgbRed: CGFloat(rgb.red), green: CGFloat(rgb.green), blue: CGFloat(rgb.blue), alpha: 1)
    }

    /// An atlas image filled with the body color, ready for the numerals.
    static func bodyContext(width: Int, height: Int, palette: TableDiePalette) -> CGContext? {
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.setFillColor(cgColor(palette.body))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context
    }

    /// Draws a numeral centered at `center` (atlas pixels, y down). Upright on the image unless
    /// `pointing` says where its top points to, as a direction on the image (y down).
    static func drawNumeral(
        _ text: String,
        at center: CGPoint,
        fontSize: CGFloat,
        underlined: Bool,
        pointing: CGVector = CGVector(dx: 0, dy: -1),
        color: CGColor,
        imageHeight: Int,
        in context: CGContext
    ) {
        let font = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, fontSize, nil)
        let attributes: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color]
        let line = CTLineCreateWithAttributedString(
            CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary)
        )
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        // The context's y axis points up, an atlas's down. Turning the context about the center
        // by this angle takes the top of the numeral to `pointing`.
        let centerY = CGFloat(imageHeight) - center.y
        context.saveGState()
        context.translateBy(x: center.x, y: centerY)
        context.rotate(by: atan2(-pointing.dx, -pointing.dy))
        context.textPosition = CGPoint(x: -bounds.midX, y: -bounds.midY)
        CTLineDraw(line, context)
        if underlined {
            context.setFillColor(color)
            let barY = -bounds.height / 2 - fontSize * 0.12
            context.fill(CGRect(x: -bounds.width / 2, y: barY, width: bounds.width, height: fontSize * 0.07))
        }
        context.restoreGState()
    }
}
#endif
