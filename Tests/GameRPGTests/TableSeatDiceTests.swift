// @copyright André Trettin

#if (os(iOS) || os(macOS) || os(visionOS)) && canImport(Testing)
import Foundation
import Testing

@testable import GameRPG

@Suite("Dice of a seat on the 3D table")
struct TableSeatDiceTests {
    @Test("The dice take the pool's slots in the order of the dice set, d20 and d6 mixed")
    func slotsFollowTheSet() {
        let slots = TableSeatDice.slots(sides: [6, 20, 20, 6], poolSize: 6)

        #expect(slots == [
            .init(isD20: false, slot: 0, index: 0),
            .init(isD20: true, slot: 0, index: 1),
            .init(isD20: true, slot: 1, index: 2),
            .init(isD20: false, slot: 1, index: 3)
        ])
    }

    @Test("Dice without a mesh or beyond the pool are left out, the others keep their order")
    func slotsSkipWhatTheTableLacks() {
        let slots = TableSeatDice.slots(sides: [20, 12, 20, 6, 20, 100, 6], poolSize: 2)

        #expect(slots.map(\.index) == [0, 2, 3, 6])
        #expect(slots.map(\.isD20) == [true, true, false, false])
        #expect(slots.map(\.slot) == [0, 1, 0, 1])
    }

    /// The seats of `PlayerSeat.seatPoses`: position, rotation, and the direction that is "right"
    /// for a player sitting there and looking at the table.
    @Test(
        "The first die of a set is the leftmost one for the player at the seat",
        arguments: [
            (x: 0.0, z: 2.0, degrees: 0.0, right: (x: 1.0, z: 0.0)),
            (x: -1.5, z: 0.5, degrees: 270.0, right: (x: 0.0, z: 1.0)),
            (x: 1.5, z: 0.5, degrees: 90.0, right: (x: 0.0, z: -1.0)),
            (x: -1.5, z: -0.5, degrees: 270.0, right: (x: 0.0, z: 1.0)),
            (x: 1.5, z: -0.5, degrees: 90.0, right: (x: 0.0, z: -1.0)),
            (x: 0.0, z: -2.0, degrees: 180.0, right: (x: -1.0, z: 0.0))
        ]
    )
    func positionsReadLeftToRight(seat: (x: Double, z: Double, degrees: Double, right: (x: Double, z: Double))) {
        let positions = TableSeatDice.positions(
            seatPosition: (seat.x, seat.z),
            rotation: seat.degrees * .pi / 180,
            count: 3
        )
        let alongRight = positions.map { $0.x * seat.right.x + $0.z * seat.right.z }

        #expect(positions.count == 3)
        #expect(zip(alongRight, alongRight.dropFirst()).allSatisfy { abs($1 - $0 - TableSeatDice.spacing) < 0.000_1 })
        // Centered on the seat, on the table, just inside the seat's own edge.
        let seatAlongRight = seat.x * seat.right.x + seat.z * seat.right.z
        #expect(abs(alongRight[1] - seatAlongRight) < 0.000_1)
        #expect(positions.allSatisfy {
            abs($0.x) <= Double(GameMetrics.tableWidth) / 2 && abs($0.z) <= Double(GameMetrics.tableLength) / 2
        })
        #expect(TableSeatDice.positions(seatPosition: (seat.x, seat.z), rotation: 0, count: 0).isEmpty)
    }
}
#endif
