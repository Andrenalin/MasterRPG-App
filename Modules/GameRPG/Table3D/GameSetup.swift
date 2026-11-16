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
final class GameSetup {
    let root: Entity
    var setup: TableSetup
    let board: Board
    var pinPawns: [PinPawn] = []
    var roomHitAreas: [RoomHitArea] = []
    var seats: [PlayerSeat] = []
    /// Max pool size, per seat, for each die type — see `playerD20Ids`/`playerD3Ids`/`playerD4Ids`/`playerD12Ids`/`playerD10Ids`/`playerD8Ids`/`playerD6Ids`.
    static let maxDicePerType = 6
    /// Each seat's own pre-allocated D20 pool, keyed by seat — created once
    /// here, alongside the seats themselves, since TabletopKit equipment
    /// (unlike `PinPawn`) can't be added once `TableSetup` is frozen. Sized
    /// to `maxDicePerType` so `GameTableModel.applyDiceRoll` can mirror any
    /// locally focused dice set up to that many d20s; every slot starts
    /// parked off-table (`initialState.pose = .parkedDicePose`, `.value = 0`)
    /// until a roll actually claims it. See `playerD6Ids` for the matching
    /// d6 pool — together they're how a focused set "mixes" die types.
    var playerD20Ids: [TableSeatIdentifier: [EquipmentIdentifier]] = [:]
    /// The d6 counterpart to `playerD20Ids` — same pool sizing and hidden-
    /// until-claimed behavior, backed by `Die` (a d6 mesh) instead of `Die20`.
    var playerD6Ids: [TableSeatIdentifier: [EquipmentIdentifier]] = [:]
    /// The d8 pool, the same way: backed by `Die8`, a mesh generated in code.
    var playerD8Ids: [TableSeatIdentifier: [EquipmentIdentifier]] = [:]
    /// The d10 pool, the same way: backed by `Die10`, a mesh generated in code.
    var playerD10Ids: [TableSeatIdentifier: [EquipmentIdentifier]] = [:]
    /// The d12 pool, the same way: backed by `Die12`, a mesh generated in code.
    var playerD12Ids: [TableSeatIdentifier: [EquipmentIdentifier]] = [:]
    /// The d4 pool, the same way: backed by `Die4`, a mesh generated in code.
    var playerD4Ids: [TableSeatIdentifier: [EquipmentIdentifier]] = [:]
    /// The d3 pool, the same way: backed by `Die3`, the d6's mesh with a texture of its own.
    var playerD3Ids: [TableSeatIdentifier: [EquipmentIdentifier]] = [:]

    /// A seat's pool of one die kind.
    func dieIds(_ kind: TableDieKind, seat: TableSeatIdentifier) -> [EquipmentIdentifier]? {
        switch kind {
            case .d20: playerD20Ids[seat]
            case .d12: playerD12Ids[seat]
            case .d4: playerD4Ids[seat]
            case .d3: playerD3Ids[seat]
            case .d10: playerD10Ids[seat]
            case .d8: playerD8Ids[seat]
            case .d6: playerD6Ids[seat]
        }
    }
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
     A 1.5 m × 2 m table (`GameMetrics.tableWidth`/`tableLength`, X/Z
     respectively) with the map centered in a 0.25 m margin
     (`GameMetrics.mapMargin`) and six seats around it: the master centered
     on the near (+Z, South) short edge — the side the volumetric window's
     own default viewing position, and this view's ornament,
     already face (see `WindowVisionList`, `GameTableView`) — with the
     table's long sides running away from the viewer along Z instead of
     spanning left-right in front of them. Four more seats flank those long
     (West/East) sides in two bands, near master first, then the guest seat
     opposite the master on the far (-Z, North) short edge — see
     `PlayerSeat.seatPoses`. Each seat's own dice sit in that margin,
     between the map and the seat itself (`PlayerSeat.diceLayout`). Without
     an active SharePlay session there's no per-participant spatial
     coordination to face the viewer toward whichever seat they claim (that's
     `TabletopGame.coordinateWithSession(_:)`'s job once a session exists —
     see `RPGSharePlayController`), so the master's own seat is placed here,
     near-edge, to already line up with a solo tester's fixed vantage.

              North: guest seat (far, index 5)
                         +--+
                         |#6|
                         +--+
       +----------------------------------+
       |          0.25 m margin            |
  +--+ |   +--------------------+          | +--+
  |#3| |   |                    |          | |#4|
  +--+ |   |        map         |          | +--+
 (west)|   |                    |          |(east)
  +--+ |   +--------------------+          | +--+
  |#1| |          0.25 m margin            | |#2|
  +--+ +----------------------------------+ +--+
 (west)                                    (east)
                         +--+
                         |GM|
                         +--+
              South (near, +Z, viewer-facing)
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

            // A pool of `Self.maxDicePerType` D20s and the same number of D3s, D4s, D12s, D10s, D8s and D6s per seat, created up
            // front like the seats themselves — TabletopKit equipment can't be added once
            // `TableSetup` is frozen. `GameTableModel.applyDiceRoll` reveals exactly as many of each
            // type as the locally focused dice set needs, repositioning them into a compact layout;
            // the rest stay parked off-table (a synced pose rather than a locally-disabled entity,
            // see `TableVisualState.Pose2D.parkedDicePose`) until `applyDiceRoll` claims them.
            // `seatControl` stays `.any`: on-device testing showed seat-restricted equipment never
            // rendered for any player, master included. Ownership is instead enforced at
            // interaction time — `GameInteraction.shouldAcceptInteraction` only lets a die's owner
            // (or the game master) pick it up.
            var d20Ids: [EquipmentIdentifier] = []
            var d6Ids: [EquipmentIdentifier] = []
            var d8Ids: [EquipmentIdentifier] = []
            var d10Ids: [EquipmentIdentifier] = []
            var d12Ids: [EquipmentIdentifier] = []
            var d4Ids: [EquipmentIdentifier] = []
            var d3Ids: [EquipmentIdentifier] = []
            for slot in 0 ..< Self.maxDicePerType {
                let d20 = Die20(
                    id: EquipmentIdentifier(idGenerator.newId()),
                    seatIndex: index,
                    dieNumber: slot + 1
                )
                setup.add(equipment: d20)
                d20Ids.append(d20.id)

                let d6 = Die(
                    id: EquipmentIdentifier(idGenerator.newId()),
                    seatIndex: index,
                    dieNumber: slot + 1
                )
                setup.add(equipment: d6)
                d6Ids.append(d6.id)

                let d8 = Die8(
                    id: EquipmentIdentifier(idGenerator.newId()),
                    seatIndex: index,
                    dieNumber: slot + 1
                )
                setup.add(equipment: d8)
                d8Ids.append(d8.id)

                let d10 = Die10(
                    id: EquipmentIdentifier(idGenerator.newId()),
                    seatIndex: index,
                    dieNumber: slot + 1
                )
                setup.add(equipment: d10)
                d10Ids.append(d10.id)

                let d12 = Die12(
                    id: EquipmentIdentifier(idGenerator.newId()),
                    seatIndex: index,
                    dieNumber: slot + 1
                )
                setup.add(equipment: d12)
                d12Ids.append(d12.id)

                let d4 = Die4(
                    id: EquipmentIdentifier(idGenerator.newId()),
                    seatIndex: index,
                    dieNumber: slot + 1
                )
                setup.add(equipment: d4)
                d4Ids.append(d4.id)

                let d3 = Die3(
                    id: EquipmentIdentifier(idGenerator.newId()),
                    seatIndex: index,
                    dieNumber: slot + 1
                )
                setup.add(equipment: d3)
                d3Ids.append(d3.id)
            }
            playerD20Ids[seatId] = d20Ids
            playerD6Ids[seatId] = d6Ids
            playerD8Ids[seatId] = d8Ids
            playerD10Ids[seatId] = d10Ids
            playerD12Ids[seatId] = d12Ids
            playerD4Ids[seatId] = d4Ids
            playerD3Ids[seatId] = d3Ids
        }

        // The board is a static root-owned surface. Keeping it out of
        // TabletopKit prevents its automatic tabletop resting transform from
        // moving the plane inside the bottom-origin wood mesh.
        board = Board()
        root.addChild(board.entity)
    }
}
#endif
