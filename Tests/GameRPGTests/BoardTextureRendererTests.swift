// @copyright André Trettin

#if (os(iOS) || os(macOS) || os(visionOS)) && canImport(Testing)
import CoreGraphics
import CoreRPG
import Foundation
import MapRPG
import SwiftUI
import Testing

@testable import GameRPG

@Suite("Board texture fog of war")
@MainActor
struct BoardTextureRendererTests {
    /// A 100×100 photo: the top-left quadrant is red, everything else blue.
    private static func photo() throws -> AKImage {
        let context = try #require(CGContext(
            data: nil,
            width: 100,
            height: 100,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        // Core Graphics is bottom-left-origin: y 50...100 is the visual top half.
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 50, width: 50, height: 50))
        let cgImage = try #require(context.makeImage())
#if os(macOS)
        return AKImage(cgImage: cgImage, size: CGSize(width: 100, height: 100))
#else
        return AKImage(cgImage: cgImage)
#endif
    }

    /// A map whose right half is one hidden room, with the given tile selection.
    private static func map(tileCoordinates: [CGPoint]) -> MapModel {
        MapModel(
            id: UUID(),
            name: "Tiles",
            entries: [
                MapEntryModel(
                    id: UUID(),
                    name: "Hidden",
                    content: "",
                    coordinates: [
                        CGPoint(x: 50, y: 0),
                        CGPoint(x: 100, y: 0),
                        CGPoint(x: 100, y: 100),
                        CGPoint(x: 50, y: 100)
                    ],
                    isShown: false
                )
            ],
            displayConfig: DisplayConfigModel(
                tileCoordinates: tileCoordinates,
                color: .black,
                border: DisplayBorderViewModel()
            ),
            width: 100,
            height: 100
        )
    }

    private static let redQuadrant = [
        CGPoint(x: 0, y: 0),
        CGPoint(x: 50, y: 0),
        CGPoint(x: 50, y: 50),
        CGPoint(x: 0, y: 50)
    ]

    private func render(tileCoordinates: [CGPoint], isGameMaster: Bool = false) async throws -> CGImage {
        let input = try #require(BoardTextureInput(
            image: Self.photo(),
            degrees: 0,
            mapModel: Self.map(tileCoordinates: tileCoordinates),
            isGameMaster: isGameMaster
        ))
        return try #require(await BoardTextureRenderer.render(input))
    }

    @Test("A configured tile repeats inside a player's hidden room, like the 2D fog")
    func tileFillsHiddenRoom() async throws {
        let texture = try await render(tileCoordinates: Self.redQuadrant)

        // Both repeats of the red tile across the hidden right half.
        #expect(try TexturePixel(texture, x: 75, y: 25).isRed)
        #expect(try TexturePixel(texture, x: 75, y: 75).isRed)
        // The shown left half keeps the photo.
        #expect(try TexturePixel(texture, x: 25, y: 75).isBlue)
    }

    /// CODE_AUDIT_19 §5.18: the repeat period is the tile's exact size. Snapping it to whole
    /// texture pixels made the 3D lattice drift from the 2D one on large maps.
    @Test("The fog tile keeps its exact rect as the repeat period")
    func fogTileKeepsExactPeriod() throws {
        let pixelSize = CGSize(width: 2048, height: 2048)
        let context = try #require(CGContext(
            data: nil,
            width: Int(pixelSize.width),
            height: Int(pixelSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let canvas = CGSize(width: 3000, height: 3000)
        let tile = CGRect(x: 10.3, y: 20.7, width: 33.3, height: 41.9)

        let fogTile = try #require(BoardTextureRenderer.fogTileImage(tile, from: context, canvas: canvas, pixelSize: pixelSize))

        #expect(abs(fogTile.rect.minX - tile.minX) < 1e-9)
        #expect(abs(fogTile.rect.minY - tile.minY) < 1e-9)
        #expect(abs(fogTile.rect.width - tile.width) < 1e-9)
        #expect(abs(fogTile.rect.height - tile.height) < 1e-9)
    }

    /// CODE_AUDIT_19 §5.18: the 3D board uses the 2D per-room tile budget, so a room that needs
    /// more tiles than 2D draws gets solid fog in both.
    @Test("A room needing more tiles than the 2D budget gets solid fog")
    func tileBudgetMatchesTwoDimensionalMap() {
        let tile = CGRect(x: 0, y: 0, width: 1, height: 1)
        #expect(MapFogTileBudget.allowsTiling(roomBounds: CGRect(x: 0, y: 0, width: 50, height: 50), tileRectangle: tile))
        #expect(!MapFogTileBudget.allowsTiling(roomBounds: CGRect(x: 0, y: 0, width: 100, height: 100), tileRectangle: tile))
    }

    @Test("Without a complete tile selection the hidden room stays solid fog")
    func incompleteTileFallsBackToSolidFog() async throws {
        let texture = try await render(tileCoordinates: Array(Self.redQuadrant.prefix(3)))

        #expect(try TexturePixel(texture, x: 75, y: 25).isBlack)
        #expect(try TexturePixel(texture, x: 75, y: 75).isBlack)
    }

    @Test("The game master sees the photo under the room overlay, never the tile")
    func gameMasterIgnoresTile() async throws {
        let texture = try await render(tileCoordinates: Self.redQuadrant, isGameMaster: true)

        let pixel = try TexturePixel(texture, x: 75, y: 75)
        #expect(!pixel.isRed)
        #expect(pixel.blue > pixel.red)
    }
}

/// One pixel of a rendered texture, sampled in top-left-origin image coordinates.
private struct TexturePixel {
    let red: UInt8
    let green: UInt8
    let blue: UInt8

    init(_ image: CGImage, x: Int, y: Int) throws {
        var bytes = [UInt8](repeating: 0, count: 4)
        let didDraw = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            // Shift the image so the requested pixel covers the 1×1 context. Image row `y` counts
            // from the top; the context's y-axis counts from the bottom.
            context.draw(
                image,
                in: CGRect(
                    x: -x,
                    y: y - image.height + 1,
                    width: image.width,
                    height: image.height
                )
            )
            return true
        }
        try #require(didDraw)
        red = bytes[0]
        green = bytes[1]
        blue = bytes[2]
    }

    var isRed: Bool { red > 200 && green < 60 && blue < 60 }
    var isBlue: Bool { blue > 200 && red < 60 && green < 60 }
    var isBlack: Bool { red < 30 && green < 30 && blue < 30 }
}
#endif
