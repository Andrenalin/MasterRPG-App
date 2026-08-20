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
    /// Max pool size, per seat, for each die type — see `playerD20Ids`/`playerD6Ids`.
    static let maxDicePerType = 6
    /// Each seat's own pre-allocated D20 pool, keyed by seat — created once
    /// here, alongside the seats themselves, since TabletopKit equipment
    /// (unlike `PinPawn`) can't be added once `TableSetup` is frozen. Sized
    /// to `maxDicePerType` so `GameTableModel.applyDiceRoll` can mirror any
    /// locally focused dice set up to that many d20s; every slot starts
    /// hidden (`Die20.entity.isEnabled = false`, `initialState.value = 0`)
    /// until a roll actually claims it. See `playerD6Ids` for the matching
    /// d6 pool — together they're how a focused set "mixes" die types.
    var playerD20Ids: [TableSeatIdentifier: [EquipmentIdentifier]] = [:]
    /// The d6 counterpart to `playerD20Ids` — same pool sizing and hidden-
    /// until-claimed behavior, backed by `Die` (a d6 mesh) instead of `Die20`.
    var playerD6Ids: [TableSeatIdentifier: [EquipmentIdentifier]] = [:]
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
     A 2 m × 1.5 m table (`GameMetrics.tableLength`/`tableWidth`) with the
     map centered in a 0.25 m margin (`GameMetrics.mapMargin`) and six
     seats around it: the master alone at the west end, two players along
     each long side, and one more player at the east end — see
     `PlayerSeat.seatPoses`. Each seat's own dice sit in that margin,
     between the map and the seat itself (`PlayerSeat.diceLayout`).

                     north: 2 seats
              +--+                    +--+
              |##|                    |##|
              +--+                    +--+
     +--+   +----------------------------+   +--+
     |GM|   |         0.25 m margin      |   |E5|
     +--+   |   +--------------------+   |   +--+
    (west)  |   |                    |   |  (east)
             |   |        map         |   |
             |   |                    |   |
             |   +--------------------+   |
             |         0.25 m margin      |
             +----------------------------+
              +--+                    +--+
              |##|                    |##|
              +--+                    +--+
                     south: 2 seats
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

            // A pool of `Self.maxDicePerType` D20s and the same number of
            // D6s per seat, created up front like the seats themselves —
            // TabletopKit equipment can't be added once `TableSetup` is
            // frozen. `GameTableModel.applyDiceRoll` reveals exactly as many
            // of each type as the locally focused dice set needs; the rest
            // stay hidden (see `Die20`/`Die.init`). Initial poses here are
            // mostly nominal — every slot starts hidden, and the ones that
            // do get shown are repositioned into a compact layout sized to
            // just the active count. `seatControl` stays `.any`, matching
            // the original single shared die: on-device testing showed
            // seat-restricted equipment never rendered for *any* player,
            // master included, and TabletopKit's docs don't fully specify
            // whether `ControllingSeats.restricted` also affects per-device
            // rendering (vs. only interaction). Ownership here is visual/
            // positional only.
            let dicePoses = PlayerSeat.diceLayout(inFrontOf: pose, count: Self.maxDicePerType * 2)
            var d20Ids: [EquipmentIdentifier] = []
            var d6Ids: [EquipmentIdentifier] = []
            for slot in 0 ..< Self.maxDicePerType {
                let d20 = Die20(
                    id: EquipmentIdentifier(idGenerator.newId()),
                    pose: dicePoses[slot],
                    seatIndex: index,
                    dieNumber: slot + 1
                )
                setup.add(equipment: d20)
                d20Ids.append(d20.id)

                let d6 = Die(
                    id: EquipmentIdentifier(idGenerator.newId()),
                    pose: dicePoses[Self.maxDicePerType + slot],
                    seatIndex: index,
                    dieNumber: slot + 1
                )
                setup.add(equipment: d6)
                d6Ids.append(d6.id)
            }
            playerD20Ids[seatId] = d20Ids
            playerD6Ids[seatId] = d6Ids
        }

        // The board is a static root-owned surface. Keeping it out of
        // TabletopKit prevents its automatic tabletop resting transform from
        // moving the plane inside the bottom-origin wood mesh.
        board = Board()
        root.addChild(board.entity)
    }
}
#endif
