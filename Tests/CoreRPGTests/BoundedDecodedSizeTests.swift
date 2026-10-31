// @copyright André Trettin

import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#else
import UIKit
#endif

@testable import CoreRPG

/// The map repair measures every map's photo. `boundedDecodedSize` reads that size from the header,
/// so it has to give exactly what the decode would, or the repair would see a changed canvas.
@Suite("Bounded decoded size")
struct BoundedDecodedSizeTests {
    private static func jpeg(width: Int, height: Int, orientation: Int? = nil) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())

        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        let properties: [CFString: Any] = orientation.map { [kCGImagePropertyOrientation: $0] } ?? [:]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        try #require(CGImageDestinationFinalize(destination))
        return data as Data
    }

    @Test("The header size equals the size of the decoded image", arguments: [1, 2, 3, 4, 5, 6, 7, 8])
    func matchesTheDecode(orientation: Int) throws {
        let data = try Self.jpeg(width: 120, height: 70, orientation: orientation)

        let headerSize = try #require(AKImage.boundedDecodedSize(from: data))
        let decodedSize = try #require(AKImage.boundedDecode(from: data)).size

        #expect(headerSize == decodedSize)
        #expect(headerSize == ((5...8).contains(orientation) ? CGSize(width: 70, height: 120) : CGSize(width: 120, height: 70)))
    }

    @Test("A file without an orientation is read as it is")
    func noOrientation() throws {
        let data = try Self.jpeg(width: 33, height: 51)

        #expect(AKImage.boundedDecodedSize(from: data) == CGSize(width: 33, height: 51))
    }

    @Test("The file variant reads the same size")
    func fileVariant() throws {
        let url = URL.temporaryDirectory.appending(path: "BoundedDecodedSizeTests-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        try Self.jpeg(width: 90, height: 40, orientation: 6).write(to: url)

        #expect(AKImage.boundedDecodedSize(from: url) == CGSize(width: 40, height: 90))
        #expect(AKImage.boundedDecodedSize(from: url) == AKImage.boundedDecode(from: url)?.size)
    }

    @Test("An image beyond the decode bound is left to the decode, which scales it")
    func beyondTheBound() throws {
        let data = try Self.jpeg(width: 200, height: 100)

        #expect(AKImage.boundedDecodedSize(from: data, maxPixelSize: 150) == nil)
        #expect(AKImage.boundedDecodedSize(from: data, maxPixelSize: 200) == CGSize(width: 200, height: 100))
    }

    @Test("Data that is no image has no size")
    func notAnImage() {
        #expect(AKImage.boundedDecodedSize(from: Data("not an image".utf8)) == nil)
        #expect(AKImage.boundedDecodedSize(from: Data()) == nil)
    }
}
