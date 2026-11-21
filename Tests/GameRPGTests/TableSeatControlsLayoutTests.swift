// @copyright André Trettin

#if (os(iOS) || os(macOS) || os(visionOS)) && canImport(Testing)
import Foundation
import simd
import Testing

@testable import GameRPG

@Suite("Seat control panel layout")
struct TableSeatControlsLayoutTests {
    /// Every seat's rotation, as in `PlayerSeat.seatPoses` (the master's, then the two near and two
    /// far side seats, then the guest's).
    private static let degrees: [Double] = [0, 270, 90, 270, 90, 180]
    private static let planeWidth = 0.9
    private static let planeDepth = 1.4

    private func edge(_ side: TableSeatControlsLayout.Side, _ radians: Double) -> Double {
        TableSeatControlsLayout.mapEdge(side, rotation: radians, planeWidth: Self.planeWidth, planeDepth: Self.planeDepth)
    }

    private func placement(
        _ side: TableSeatControlsLayout.Side, _ radians: Double, width: Double = 0.3, stackedAbove: Double = 0
    ) -> TableSeatControlsLayout.Placement {
        TableSeatControlsLayout.edgeAlignedPlacement(
            side: side, rotation: radians, edgeLateral: edge(side, radians), width: width, stackedAbove: stackedAbove
        )
    }

    private func lateralPosition(_ placement: TableSeatControlsLayout.Placement, _ radians: Double) -> Double {
        Double(placement.position.x) * cos(radians) - Double(placement.position.z) * sin(radians)
    }

    @Test("The panel faces the seated player: yaw is the seat's rotation, tilted back")
    func panelFacesThePlayer() {
        for degrees in Self.degrees {
            let radians = degrees * .pi / 180
            let result = placement(.leading, radians)
            #expect(abs(Double(result.yaw) - radians) < 1e-5)
            #expect(result.pitch == TableSeatControlsLayout.tilt)
            // The panel's face normal points toward the seat's edge and up.
            let normal = result.orientation.act(SIMD3<Float>(0, 0, 1))
            #expect(normal.y > 0)
            let direction = SIMD3<Float>(Float(sin(result.yaw)), 0, Float(cos(result.yaw)))
            #expect(simd_dot(normal, direction) > 0.5)
        }
    }

    @Test("The map starts at the player's left and ends at their right, for every seat")
    func mapEdges() {
        // A map plane 0.9 wide (X) and 1.4 deep (Z). The end seats look along Z, so the plane's
        // width runs along their edge; the side seats look along X, so its depth does.
        for (index, degrees) in Self.degrees.enumerated() {
            let radians = degrees * .pi / 180
            let half = (index == 0 || index == 5) ? 0.45 : 0.7
            #expect(abs(edge(.leading, radians) + half) < 1e-9)
            #expect(abs(edge(.trailing, radians) - half) < 1e-9)
        }
    }

    @Test("A leading panel starts where the map starts, a trailing one ends where it ends")
    func panelsStandAtTheMapEdges() {
        for degrees in Self.degrees {
            let radians = degrees * .pi / 180
            for width in [0.12, 0.35] {
                let leading = placement(.leading, radians, width: width)
                #expect(abs((lateralPosition(leading, radians) - width / 2) - edge(.leading, radians)) < 1e-5)
                let trailing = placement(.trailing, radians, width: width)
                #expect(abs((lateralPosition(trailing, radians) + width / 2) - edge(.trailing, radians)) < 1e-5)
            }
        }
    }

    @Test("The leading edge is the player's left: it lies on the same side as the dice row's first die")
    func leadingIsTheLeftOfTheDice() {
        for degrees in Self.degrees {
            let radians = degrees * .pi / 180
            let dice = TableSeatDice.positions(seatPosition: (0, 0), rotation: radians, count: 3)
            let lateral = (x: cos(radians), z: -sin(radians))
            let first = (dice.first?.x ?? 0) * lateral.x + (dice.first?.z ?? 0) * lateral.z
            let last = (dice.last?.x ?? 0) * lateral.x + (dice.last?.z ?? 0) * lateral.z
            #expect(first < last)
            #expect(lateralPosition(placement(.leading, radians), radians) < lateralPosition(placement(.trailing, radians), radians))
        }
    }

    @Test("A panel too wide for the edge stays between the table's corners")
    func panelsStayBetweenTheCorners() {
        for degrees in Self.degrees {
            let radians = degrees * .pi / 180
            let limit = TableSeatControlsLayout.edgeHalfLength(rotation: radians) - TableSeatControlsLayout.cornerClearance
            for side in [TableSeatControlsLayout.Side.leading, .trailing] {
                for width in [0.3, 1.2, 3.0] {
                    let result = placement(side, radians, width: width)
                    #expect(abs(lateralPosition(result, radians)) + min(width, 2 * limit) / 2 <= limit + 1e-6)
                    #expect(abs(Double(result.position.x)) <= Double(GameMetrics.tableWidth) / 2)
                    #expect(abs(Double(result.position.z)) <= Double(GameMetrics.tableLength) / 2)
                }
            }
        }
    }

    @Test("A panel above a dock starts at the same edge, higher up the slope")
    func stackedPanelContinuesTheSlope() {
        for side in [TableSeatControlsLayout.Side.leading, .trailing] {
            let lower = placement(side, 0)
            let upper = placement(side, 0, stackedAbove: 0.2)
            let offset = upper.position - lower.position
            #expect(abs(simd_length(offset) - 0.2) < 1e-5)
            #expect(abs(offset.x) < 1e-5)
            // Up and toward the table's centre, along the tilted plane.
            #expect(offset.y > 0)
            #expect(offset.z < 0)
            #expect(abs(offset.y / (-offset.z) - 1 / tan(TableSeatControlsLayout.tilt)) < 1e-4)
        }
    }

    @Test("The panel's bottom edge rests on the table surface")
    func panelStandsOnTheSurface() {
        #expect(placement(.trailing, 0).position.y == GameMetrics.tableThickness)
    }
}
#endif
