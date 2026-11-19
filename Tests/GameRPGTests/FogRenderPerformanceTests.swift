// @copyright André Trettin

#if (os(iOS) || os(macOS) || os(visionOS)) && canImport(Testing)
import CoreGraphics
import CoreRPG
import Foundation
import MapRPG
import SwiftUI
import Testing

@testable import GameRPG

/// CODE_AUDIT_TestGaps §7.1: the 3D board texture of a large map with many rooms, for the game
/// master and for a player (who also gets the repeated fog tile). The budget (5 s) is about
/// a hundred times the 0.03 s a development Mac needs: it catches a change to quadratic work per
/// room, not a slow machine.
@Suite("Performance budgets: fog render")
@MainActor
struct FogRenderPerformanceTests {
    /// A 3 000 × 3 000 photo, larger than the 2 048 texture cap, so the downscale is part of the work.
    private static func largePhoto() throws -> AKImage {
        let side = 3_000
        let context = try #require(CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.3, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        let cgImage = try #require(context.makeImage())
        #if os(macOS)
        return AKImage(cgImage: cgImage, size: CGSize(width: side, height: side))
        #else
        return AKImage(cgImage: cgImage)
        #endif
    }

    /// A grid of `columns × columns` rooms, each a six-sided polygon; every third one is shown.
    private static func map(columns: Int, tile: [CGPoint]) -> MapModel {
        let side = 3_000.0
        let cell = side / Double(columns)
        var entries: [MapEntryModel] = []
        for row in 0..<columns {
            for column in 0..<columns {
                let x = Double(column) * cell
                let y = Double(row) * cell
                let polygon = [
                    CGPoint(x: x + cell * 0.1, y: y + cell * 0.3),
                    CGPoint(x: x + cell * 0.5, y: y + cell * 0.05),
                    CGPoint(x: x + cell * 0.9, y: y + cell * 0.3),
                    CGPoint(x: x + cell * 0.9, y: y + cell * 0.7),
                    CGPoint(x: x + cell * 0.5, y: y + cell * 0.95),
                    CGPoint(x: x + cell * 0.1, y: y + cell * 0.7)
                ]
                entries.append(MapEntryModel(id: UUID(), name: "Room \(row)-\(column)", content: "", coordinates: polygon, isShown: (row + column).isMultiple(of: 3)))
            }
        }
        return MapModel(
            id: UUID(),
            name: "Dungeon",
            entries: entries,
            displayConfig: DisplayConfigModel(tileCoordinates: tile, color: .black, border: DisplayBorderViewModel()),
            width: side,
            height: side
        )
    }

    @Test("A map with 400 rooms renders its board texture within the budget, for the master and a player",
          arguments: [true, false])
    func largeMapRendersInTime(isGameMaster: Bool) async throws {
        let tile = [CGPoint(x: 0, y: 0), CGPoint(x: 150, y: 0), CGPoint(x: 150, y: 150), CGPoint(x: 0, y: 150)]
        let input = try #require(BoardTextureInput(
            image: Self.largePhoto(),
            degrees: 0,
            mapModel: Self.map(columns: 20, tile: tile),
            isGameMaster: isGameMaster
        ))
        // A player's texture draws only the hidden rooms; the master's draws all of them.
        #expect(isGameMaster ? input.rooms.count == 400 : input.rooms.count >= 200)

        var texture: CGImage?
        let time = await ContinuousClock().measure {
            texture = await BoardTextureRenderer.render(input)
        }

        print("PERF fog render 400 rooms (master: \(isGameMaster)): \(time)")
        let image = try #require(texture)
        #expect(max(image.width, image.height) <= Int(BoardTextureRenderer.maximumDimension))
        #expect(time < .seconds(5), "rendering 400 rooms took \(time)")
    }
}
#endif
