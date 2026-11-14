// @copyright André Trettin

#if canImport(Testing)

import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import AudioRPG

/// The player bar decodes embedded artwork downsampled and refuses oversized headers.
/// See CODE_AUDIT §8.3.
@MainActor
struct AudioArtworkDecodeTests {
    private func pngData(width: Int, height: Int) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    @Test("Artwork is decoded")
    func decodesArtwork() throws {
        #expect(AudioPlayerBarViewModel.artworkImage(from: try pngData(width: 64, height: 32)) != nil)
    }

    @Test("No data and bytes that are not an image give no artwork")
    func noArtwork() {
        #expect(AudioPlayerBarViewModel.artworkImage(from: nil) == nil)
        #expect(AudioPlayerBarViewModel.artworkImage(from: Data("not an image".utf8)) == nil)
    }
}

#endif
