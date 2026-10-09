// @copyright André Trettin

import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import CoreRPG

/// CODE_AUDIT_21 §9.5: one downsampling path with the declared-size guard.
@Suite("Image downsampler")
struct ImageDownsamplerTests {
    @Test("The declared size is classified against both limits")
    func declaredSizeLimits() {
        let dimension = ImageDownsampler.maximumDeclaredDimension
        #expect(ImageDownsampler.declaredSize(width: 4_000, height: 3_000) == .withinLimits(width: 4_000, height: 3_000))
        #expect(ImageDownsampler.declaredSize(width: dimension, height: 1) == .withinLimits(width: dimension, height: 1))
        #expect(ImageDownsampler.declaredSize(width: dimension + 1, height: 1) == .overLimits)
        #expect(ImageDownsampler.declaredSize(width: 1, height: dimension + 1) == .overLimits)
        // Both axes within the limit, the pixel count over it.
        #expect(ImageDownsampler.declaredSize(width: 16_000, height: 16_000) == .overLimits)
        #expect(ImageDownsampler.declaredSize(width: 0, height: 100) == .unknown)
        #expect(ImageDownsampler.declaredSize(width: 100, height: -1) == .unknown)
    }

    @Test("An image is read from its header and decoded downsampled")
    func headerAndDownsample() throws {
        let source = try #require(CGImageSourceCreateWithData(try pngData(width: 64, height: 32) as CFData, nil))

        #expect(ImageDownsampler.declaredSize(of: source) == .withinLimits(width: 64, height: 32))
        let image = try #require(ImageDownsampler.downsampledImage(from: source, maxPixelSize: 16))
        #expect(image.width == 16)
        #expect(image.height == 8)
    }

    @Test("Data that is no image has no declared size")
    func noImage() throws {
        let source = try #require(CGImageSourceCreateWithData(Data("no image".utf8) as CFData, nil))
        #expect(ImageDownsampler.declaredSize(of: source) == .unknown)
        #expect(ImageDownsampler.downsampledImage(from: source, maxPixelSize: 16) == nil)
    }

    private func pngData(width: Int, height: Int) throws -> Data {
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }
}
