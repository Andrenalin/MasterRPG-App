// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import MapRPG

/// CODE_AUDIT_26 §5.23: "Edit Tile" opens the tile editor, not a second copy of the map editor.
@Suite("Map editor launcher")
struct MapEditorLauncherTests {
    @Test("The tile editor has its own route and window, the map editor keeps its own")
    func kindsHaveTheirOwnDestinations() {
        let id = UUID()
        #expect(MapEditorKind.map.route(for: id) == .mapEditor(id))
        #expect(MapEditorKind.tile.route(for: id) == .mapTileEditor(id))
        #expect(MapEditorKind.map.sceneId == .mapEditor)
        #expect(MapEditorKind.tile.sceneId == .mapTileEditor)
        #expect(MapEditorKind.map.sceneId != MapEditorKind.tile.sceneId)
    }
}

#if canImport(UIKit)
import UIKit

/// CODE_AUDIT_26 §5.24: the cover tile is cut from the rotated canvas, not from the raw bitmap.
@Suite("Map cover tile image")
struct MapTileImageTests {
    private func image(width: Int, height: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    @Test("A tile below the unrotated height exists on the rotated canvas")
    func rotationChangesTheCanvas() throws {
        let wide = image(width: 40, height: 20)
        let rect = CGRect(x: 0, y: 20, width: 20, height: 20)

        // Unrotated, the bitmap is 20 high: nothing lies at y = 20.
        #expect(MapTileImage.crop(wide, degrees: 0, to: rect) == nil)
        // Rotated by a quarter turn the canvas is 20 wide and 40 high: the tile is there.
        let tile = try #require(MapTileImage.crop(wide, degrees: 90, to: rect))
        #expect(tile.cgImage?.width == 20)
        #expect(tile.cgImage?.height == 20)
    }

    @Test("Without rotation the tile is the plain crop")
    func noRotationIsAPlainCrop() throws {
        let tile = try #require(MapTileImage.crop(image(width: 40, height: 20), degrees: 0, to: CGRect(x: 10, y: 5, width: 20, height: 10)))
        #expect(tile.cgImage?.width == 20)
        #expect(tile.cgImage?.height == 10)
    }
}
#endif
#endif
