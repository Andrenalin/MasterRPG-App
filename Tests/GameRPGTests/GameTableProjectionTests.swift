// @copyright André Trettin

#if (os(iOS) || os(macOS) || os(visionOS)) && canImport(Testing)
import CoreGraphics
import Foundation
import Testing

@testable import GameRPG

@Suite("Map-to-table projection")
struct GameTableProjectionTests {
    @Test("The map's stored size wins; otherwise the rotated photo size is used")
    func coordinateSizeSelection() {
        #expect(MapTableProjection.coordinateSize(
            mapWidth: 1200, mapHeight: 800, imageSize: CGSize(width: 10, height: 20), degrees: 90
        ) == CGSize(width: 1200, height: 800))
        #expect(MapTableProjection.coordinateSize(
            mapWidth: 0, mapHeight: 0, imageSize: CGSize(width: 400, height: 300), degrees: 90
        ) == CGSize(width: 300, height: 400))
        #expect(MapTableProjection.coordinateSize(
            mapWidth: 0, mapHeight: 0, imageSize: nil, degrees: 0
        ) == nil)
    }

    @Test("Positions round-trip between map and table space")
    func tablePositionRoundTrips() {
        let projection = MapTableProjection(imageSize: CGSize(width: 1200, height: 800), rotatesLandscapeMap: false)
        let location = CGPoint(x: 300, y: 600)

        let roundTripped = projection.mapLocation(for: projection.tablePosition(for: location))

        #expect(abs(roundTripped.x - location.x) < 0.01)
        #expect(abs(roundTripped.y - location.y) < 0.01)
    }

    @Test("The map center lands on the table center and drops outside the image are clamped")
    func centerAndClamping() {
        let projection = MapTableProjection(imageSize: CGSize(width: 1000, height: 1000))

        let center = projection.tablePosition(for: CGPoint(x: 500, y: 500))
        #expect(abs(center.x) < 0.0001)
        #expect(abs(center.z) < 0.0001)

        let far = projection.mapLocation(for: SIMD3<Float>(50, MapTableProjection.pinHeight, -50))
        #expect(far.x == 1000)
        #expect(far.y == 0)
    }

    @Test("A landscape map is turned a quarter turn clockwise to fill the table's long side")
    func landscapeMapIsQuarterTurned() {
        let size = CGSize(width: 1200, height: 800)
        let projection = MapTableProjection(imageSize: size, rotatesLandscapeMap: true)
        #expect(projection.isQuarterTurned)
        #expect(projection.planeWidth <= MapTableProjection.maxPlaneWidth + 0.0001)
        #expect(projection.planeDepth <= MapTableProjection.maxPlaneDepth + 0.0001)
        #expect(projection.planeDepth > projection.planeWidth)
        // Larger than the unturned plane.
        let unturned = MapTableProjection(imageSize: size, rotatesLandscapeMap: false)
        #expect(projection.planeWidth * projection.planeDepth > unturned.planeWidth * unturned.planeDepth)
        // The image's top-left corner ends up at the top-right, its top-right at the bottom-right.
        let topLeft = projection.tablePosition(for: CGPoint(x: 0, y: 0))
        #expect(abs(topLeft.x - projection.planeWidth / 2) < 0.0001)
        #expect(abs(topLeft.z + projection.planeDepth / 2) < 0.0001)
        let topRight = projection.tablePosition(for: CGPoint(x: 1200, y: 0))
        #expect(abs(topRight.x - projection.planeWidth / 2) < 0.0001)
        #expect(abs(topRight.z - projection.planeDepth / 2) < 0.0001)
        // Positions still round-trip, and a pin keeps its size relative to the map.
        let location = CGPoint(x: 300, y: 600)
        let roundTripped = projection.mapLocation(for: projection.tablePosition(for: location))
        #expect(abs(roundTripped.x - location.x) < 0.01)
        #expect(abs(roundTripped.y - location.y) < 0.01)
        #expect(abs(projection.metersPerPoint * 1200 - projection.planeDepth) < 0.0001)
    }

    @Test("Every platform turns a landscape map by default, not only visionOS")
    func landscapeMapIsTurnedByDefaultOnEveryPlatform() {
        #expect(MapTableProjection.rotatesLandscapeMapsByDefault)
        #expect(MapTableProjection(imageSize: CGSize(width: 1200, height: 800)).isQuarterTurned)
        #expect(!MapTableProjection(imageSize: CGSize(width: 800, height: 1200)).isQuarterTurned)
    }

    @Test("The map margin leaves the dice their room between the map and the table's rim")
    func marginCoversTheDice() {
        // Dice lie `diceEdgeInset` from the rim; their far side reaches half a die further.
        let diceReach = GameMetrics.diceEdgeInset + GameMetrics.maximumDieExtent / 2
        #expect(GameMetrics.mapMargin > diceReach)
        // The bigger map: the board is the table less the margin on each side.
        #expect(abs(MapTableProjection.maxPlaneWidth - (GameMetrics.tableWidth - 2 * GameMetrics.mapMargin)) < 1e-6)
        #expect(abs(MapTableProjection.maxPlaneDepth - (GameMetrics.tableLength - 2 * GameMetrics.mapMargin)) < 1e-6)
    }

    @Test("Portrait and square maps stay as they are")
    func portraitMapIsNotTurned() {
        for size in [CGSize(width: 800, height: 1200), CGSize(width: 900, height: 900)] {
            let projection = MapTableProjection(imageSize: size, rotatesLandscapeMap: true)
            #expect(!projection.isQuarterTurned)
        }
    }

    @Test("The plane fits inside the margin box for wide and tall maps")
    func planeFitsInsideBox() {
        for size in [CGSize(width: 4000, height: 500), CGSize(width: 500, height: 4000), CGSize(width: 800, height: 800)] {
            let projection = MapTableProjection(imageSize: size, rotatesLandscapeMap: false)
            #expect(projection.planeWidth <= MapTableProjection.maxPlaneWidth + 0.0001)
            #expect(projection.planeDepth <= MapTableProjection.maxPlaneDepth + 0.0001)
            let planeAspect = CGFloat(projection.planeWidth / projection.planeDepth)
            #expect(abs(planeAspect - size.width / size.height) < 0.01)
        }
    }

    @Test("The plane follows the photo's shape while positions stay normalized to the stored canvas")
    func planeFollowsPhotoNotStaleCanvas() {
        let canvas = CGSize(width: 1200, height: 800)
        let aspect = MapTableProjection.planeAspectRatio(
            photoSize: CGSize(width: 820, height: 1267), degrees: 0, canvasSize: canvas
        )
        #expect(abs(aspect - 820.0 / 1267.0) < 0.0001)

        let projection = MapTableProjection(imageSize: canvas, planeAspectRatio: aspect, rotatesLandscapeMap: false)
        #expect(abs(projection.planeDepth - MapTableProjection.maxPlaneDepth) < 0.0001)
        let corner = projection.tablePosition(for: CGPoint(x: 1200, y: 800))
        #expect(abs(corner.x - projection.planeWidth / 2) < 0.0001)
        #expect(abs(corner.z - projection.planeDepth / 2) < 0.0001)
    }

    @Test("A quarter-turned photo swaps the plane's aspect; odd angles keep the canvas' aspect")
    func planeAspectHandlesRotation() {
        let canvas = CGSize(width: 800, height: 1200)
        let turned = MapTableProjection.planeAspectRatio(
            photoSize: CGSize(width: 1200, height: 800), degrees: 90, canvasSize: canvas
        )
        #expect(abs(turned - 800.0 / 1200.0) < 0.0001)
        let odd = MapTableProjection.planeAspectRatio(
            photoSize: CGSize(width: 1200, height: 800), degrees: 45, canvasSize: canvas
        )
        #expect(abs(odd - 800.0 / 1200.0) < 0.0001)
    }
}
#endif
