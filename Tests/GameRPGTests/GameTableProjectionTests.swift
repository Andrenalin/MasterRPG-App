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
        let projection = MapTableProjection(imageSize: CGSize(width: 1200, height: 800))
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

    @Test("The plane fits inside the margin box for wide and tall maps")
    func planeFitsInsideBox() {
        for size in [CGSize(width: 4000, height: 500), CGSize(width: 500, height: 4000), CGSize(width: 800, height: 800)] {
            let projection = MapTableProjection(imageSize: size)
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

        let projection = MapTableProjection(imageSize: canvas, planeAspectRatio: aspect)
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
