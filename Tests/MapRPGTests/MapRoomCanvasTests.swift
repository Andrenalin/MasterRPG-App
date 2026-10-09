// @copyright André Trettin

#if canImport(Testing)
import CoreGraphics
import CoreRPG
import SwiftUI
import Testing

@testable import MapRPG

@MainActor
struct MapRoomCanvasTests {
    @Test func fogCoveragePreservesOppositeWindingRoomOverlap() {
        let firstPath = polygonPath([
            CGPoint(x: 0, y: 0),
            CGPoint(x: 100, y: 0),
            CGPoint(x: 100, y: 100),
            CGPoint(x: 0, y: 100)
        ])
        let oppositeWindingPath = polygonPath([
            CGPoint(x: 50, y: 50),
            CGPoint(x: 50, y: 150),
            CGPoint(x: 150, y: 150),
            CGPoint(x: 150, y: 50)
        ])
        let plan = MapFogCoveragePlan(snapshots: [
            MapRoomSnapshot(
                path: firstPath,
                bounds: firstPath.boundingRect,
                isShown: false
            ),
            MapRoomSnapshot(
                path: oppositeWindingPath,
                bounds: oppositeWindingPath.boundingRect,
                isShown: false
            )
        ])

        #expect(plan.snapshots.count == 2)
        #expect(plan.coverageDepth(at: CGPoint(x: 25, y: 25)) == 1)
        #expect(plan.coverageDepth(at: CGPoint(x: 125, y: 125)) == 1)
        #expect(plan.coverageDepth(at: CGPoint(x: 75, y: 75)) == 2)
        #expect(plan.coverageDepth(at: CGPoint(x: 175, y: 175)) == 0)
    }

    @Test func tiledFogIsPlannedPerRoomInsteadOfUsingAnAggregateLimit() {
        let tilePlanner = MapFogTilePlanner(
            tileRectangle: CGRect(x: 0, y: 0, width: 10, height: 10)
        )
        let snapshots = (0..<10).map { index in
            let origin = CGFloat(index * 250)
            let path = rectanglePath(
                CGRect(x: origin, y: 0, width: 200, height: 200)
            )
            return MapRoomSnapshot(
                path: path,
                bounds: path.boundingRect,
                isShown: false
            )
        }

        let plans = snapshots.compactMap { tilePlanner.drawPlan(for: $0) }

        #expect(plans.count == snapshots.count)
        #expect(plans.reduce(0) { $0 + $1.tileCount } > 4_096)
    }

    @Test func pathologicalTilePlanFallsBackForOnlyThatRoom() throws {
        let planner = MapFogTilePlanner(
            tileRectangle: CGRect(x: 0, y: 0, width: 10, height: 10),
            maximumTilesPerRoom: 100
        )
        let normalPath = rectanglePath(CGRect(x: 0, y: 0, width: 50, height: 50))
        let pathologicalPath = rectanglePath(CGRect(x: 0, y: 0, width: 500, height: 500))

        let normalPlan = planner.drawPlan(for: MapRoomSnapshot(
            path: normalPath,
            bounds: normalPath.boundingRect,
            isShown: false
        ))
        let pathologicalPlan = planner.drawPlan(for: MapRoomSnapshot(
            path: pathologicalPath,
            bounds: pathologicalPath.boundingRect,
            isShown: false
        ))

        #expect(normalPlan != nil)
        #expect(pathologicalPlan == nil)
    }

    // CODE_AUDIT_21 §7.8: only the rooms the viewport shows are drawn.
    @Test func visibleContentRectFollowsPanAndZoom() {
        let viewport = CGSize(width: 400, height: 200)

        let unscaled = MapPassiveRoomCanvas.visibleContentRect(transform: .identity, viewportSize: viewport)
        // Grown by the boundary stroke margin on every side.
        #expect(unscaled == CGRect(x: -16, y: -16, width: 432, height: 232))

        let zoomed = MapPassiveRoomCanvas.visibleContentRect(
            transform: ViewportTransform(scale: 2, offset: CGPoint(x: -200, y: -100)),
            viewportSize: viewport
        )
        #expect(zoomed == CGRect(x: 84, y: 34, width: 232, height: 132))
        #expect(zoomed.intersects(CGRect(x: 150, y: 80, width: 10, height: 10)))
        #expect(!zoomed.intersects(CGRect(x: 0, y: 0, width: 50, height: 20)))
    }

    @Test func visibleContentRectIsEverythingForAnUnusableTransform() {
        let viewport = CGSize(width: 400, height: 200)
        for transform in [
            ViewportTransform(scale: 0),
            ViewportTransform(scale: .nan),
            ViewportTransform(scale: 1, offset: CGPoint(x: CGFloat.infinity, y: 0))
        ] {
            let rect = MapPassiveRoomCanvas.visibleContentRect(transform: transform, viewportSize: viewport)
            #expect(rect.intersects(CGRect(x: 90_000, y: -90_000, width: 1, height: 1)))
        }
    }

    private func polygonPath(_ coordinates: [CGPoint]) -> Path {
        Path { path in
            guard let first = coordinates.first else { return }
            path.move(to: first)
            for coordinate in coordinates.dropFirst() {
                path.addLine(to: coordinate)
            }
            path.closeSubpath()
        }
    }

    private func rectanglePath(_ rectangle: CGRect) -> Path {
        Path { $0.addRect(rectangle) }
    }
}
#endif
