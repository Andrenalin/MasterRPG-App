// @copyright André Trettin

#if canImport(Testing)
import CoreGraphics
import CoreRPG
import Foundation
import Testing

@testable import MapRPG

/// CODE_AUDIT_Since_3.0.1 §5.8, §5.10: replacing a map's photo.
@MainActor
@Suite("Map photo replacement")
struct MapPhotoReplacementAuditTests {
    private func hexMap(width: CGFloat, height: CGFloat, hexSize: Double) -> MapModel {
        var grid = MapHexGridGeometry.grid(for: hexSize, in: CGRect(x: 0, y: 0, width: width, height: height))
        grid[0].isShown = true
        let room = MapEntryModel(id: UUID(), name: "Room", content: "", coordinates: [CGPoint(x: 10, y: 20)])
        return MapModel(id: UUID(), name: "Map", entries: [room] + grid, width: width, height: height, hexMapScale: hexSize, degrees: 0)
    }

    private func isRegularHexGrid(_ cells: [MapEntryModel], size: Double, width: CGFloat, height: CGFloat) -> Bool {
        let expected = MapHexGridGeometry.grid(for: size, in: CGRect(x: 0, y: 0, width: width, height: height))
        return cells.map(\.coordinates) == expected.map(\.coordinates)
    }

    @Test("Another shape gives a new regular hex grid, rooms are still stretched")
    func hexGridRebuiltOnShapeChange() throws {
        let map = hexMap(width: 120, height: 60, hexSize: 10)
        let oldCellIds = Set(map.entries.filter(\.isHexGrid).map(\.id))

        map.resetImage(with: UUID(), size: CGSize(width: 240, height: 240), degrees: 0)

        let expectedSize = MapHexGridGeometry.fittedSize(10 * sqrt(2 * 4), width: 240, height: 240)
        let cells = map.entries.filter(\.isHexGrid)
        #expect(map.hexMapScale == expectedSize)
        #expect(isRegularHexGrid(cells, size: expectedSize, width: 240, height: 240))
        #expect(oldCellIds.isDisjoint(with: cells.map(\.id)))
        #expect(cells.contains { $0.isShown }, "the revealed area carries over")
        #expect(map.entries.first { !$0.isHexGrid }?.coordinates == [CGPoint(x: 20, y: 80)])
    }

    @Test("The same shape at another size keeps a regular grid of the same cells across")
    func hexGridRebuiltOnResize() throws {
        let map = hexMap(width: 120, height: 60, hexSize: 10)

        map.resetImage(with: UUID(), size: CGSize(width: 240, height: 120), degrees: 0)

        #expect(map.hexMapScale == 20)
        #expect(isRegularHexGrid(map.entries.filter(\.isHexGrid), size: 20, width: 240, height: 120))
    }

    @Test("A shape change is detected, including the photo's rotation")
    func shapeChangeDetection() {
        let map = MapModel(id: UUID(), name: "Map", width: 100, height: 50, degrees: 0)

        #expect(!map.changesAspectRatio(forImageSize: CGSize(width: 200, height: 100), degrees: 0))
        #expect(!map.changesAspectRatio(forImageSize: CGSize(width: 201, height: 100), degrees: 0))
        #expect(map.changesAspectRatio(forImageSize: CGSize(width: 200, height: 150), degrees: 0))
        #expect(!map.changesAspectRatio(forImageSize: CGSize(width: 50, height: 100), degrees: 90))
        #expect(map.changesAspectRatio(
            forImageSize: CGSize(width: 200, height: 100),
            degrees: 0,
            comparedTo: MapImageGeometry(size: CGSize(width: 100, height: 100), degrees: 0)
        ))
    }

    @Test("A photo replaced during a game is shared with the next send")
    func replacementDuringGameIsMarkedForSharing() async throws {
        let root = try await MockRoot.importTestData()
        let itemId = try #require(root.itemController.itemDataModel.items.first)
        let replacement = PhotoReplacement(itemId: itemId, photoId: UUID(), imageSize: CGSize(width: 300, height: 200), degrees: 0, previousImage: nil)

        root.editController.apply(replacement, adaptContent: true)
        #expect(!root.rootModel.mapsWithUnsharedStructure.contains(itemId), "outside a game nothing is shared")

        root.itemController.itemDataModel.isGameMode = true
        let second = PhotoReplacement(itemId: itemId, photoId: UUID(), imageSize: CGSize(width: 600, height: 400), degrees: 0, previousImage: nil)
        root.editController.apply(second, adaptContent: true)
        #expect(root.rootModel.mapsWithUnsharedStructure.contains(itemId))
        root.itemController.itemDataModel.isGameMode = false
    }
}
#endif
