// @copyright André Trettin

#if os(visionOS)
import TabletopKit
import RealityKit
import SwiftUI
import RPGTabletopGameContent
import Spatial
import os.log
import MapRPG
import CoreRPG

@MainActor
class GameSetup {
    let root: Entity
    var setup: TableSetup
    let board: Board
    var pinPawns: [PinPawn] = []
    var roomHitAreas: [RoomHitArea] = []
    var seats: [PlayerSeat] = []
    /// Each seat's own pre-allocated d20 pair, keyed by seat — created once
    /// here, alongside the seats themselves, since TabletopKit equipment
    /// (unlike `PinPawn`) can't be added once `TableSetup` is frozen.
    /// `GameTableModel.applyDiceRoll` looks these up by the local player's
    /// own seat to mirror a character-sheet roll onto the table.
    var playerDiceIds: [TableSeatIdentifier: [EquipmentIdentifier]] = [:]
    /// Container for dynamically-added pin entities. Parented to root so they
    /// appear in the scene without going through TabletopKit's frozen TableSetup.
    let pinContainer: Entity
    /// Container for invisible room fog hit-test volumes, parallel to `pinContainer`.
    let roomHitContainer: Entity

    // This is an incrementing counter to generate unique IDs for each piece of equipment.
    struct IdentifierGenerator {
        private var count = 0

        mutating func newId() -> Int {
            count += 1
            return count
        }
    }
    var idGenerator = IdentifierGenerator()

    /*
     The table has a board in the center,
     with a hand and a pawn for each player around the sides.
     The side without a seat has the deck and the die.
     
            +---+
            |die|   +------+
            +---+   | deck |
                    +------+
       pawn
       +-+     +---+-+-+-+-+-+-+---+
       +-+     |   | | | | | | |   |
               +---+-+-+-+-+-+-+---+  +-----+
     +-----+   |---|           |---|  |     |
     |     |   |---|           |---|  |hand |
     |hand |   |---|  board    |---|  |     |
     |     |   |---|           |---|  |     |
     |     |   |---|           |---|  |     |
     |     |   +---+-+-+-+-+-+-+---+  +-----+
     +-----+   |   | | | | | | |   |
               +---+-+-+-+-+-+-+---+    +-+
                                        +-+
           +-+   +-----------+          pawn
           +-+   |           |
           pawn  |   hand    |
                 +-----------+
     */
    init(root: Entity) {
        self.root = root
        PinComponent.registerComponent()
        RoomComponent.registerComponent()
        BoardSurfaceComponent.registerComponent()
        pinContainer = Entity()
        pinContainer.name = "PinContainer"
        root.addChild(pinContainer)
        roomHitContainer = Entity()
        roomHitContainer.name = "RoomHitContainer"
        root.addChild(roomHitContainer)
        setup = TableSetup(tabletop: Table())

        for (index, pose) in PlayerSeat.seatPoses.enumerated() {
            let seatId = TableSeatIdentifier(index)
            let seat = PlayerSeat(id: seatId, pose: pose)
            seats.append(seat)
            setup.add(seat: seat)

            // Two d20s per seat, positioned in front of that seat and
            // created up front like the seats themselves — TabletopKit
            // equipment can't be added once `TableSetup` is frozen.
            // `seatControl` stays `.any`, matching the original single
            // shared die: on-device testing showed seat-restricted equipment
            // never rendered for *any* player, master included, and
            // TabletopKit's docs don't fully specify whether
            // `ControllingSeats.restricted` also affects per-device
            // rendering (vs. only interaction). Ownership here is visual/
            // positional only.
            let dicePoses = PlayerSeat.diceLayout(inFrontOf: pose)
            let firstD20 = Die20(id: EquipmentIdentifier(idGenerator.newId()), pose: dicePoses[0], seatIndex: index, dieNumber: 1)
            let secondD20 = Die20(id: EquipmentIdentifier(idGenerator.newId()), pose: dicePoses[1], seatIndex: index, dieNumber: 2)
            setup.add(equipment: firstD20)
            setup.add(equipment: secondD20)
            playerDiceIds[seatId] = [firstD20.id, secondD20.id]
        }

        // The board is a static root-owned surface. Keeping it out of
        // TabletopKit prevents its automatic tabletop resting transform from
        // moving the plane inside the bottom-origin wood mesh.
        board = Board()
        root.addChild(board.entity)
    }
}
#endif
