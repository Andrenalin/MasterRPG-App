// @copyright André Trettin

#if canImport(Testing)
import CoreGraphics
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
}
#endif
