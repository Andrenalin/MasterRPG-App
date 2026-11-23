// @copyright André Trettin

#if os(visionOS)
import Foundation
import Spatial
import TabletopKit

struct PlayerSeat: TableSeat {
    let id: ID
    var initialState: TableSeatState

    /* Six seats around the rectangular table: the master (index 0) centered
    on the near (+Z, South, viewer-facing) short edge, with the table's
    long sides running away from the viewer along Z rather than spanning
    left-right in front of them. Four more seats flank those long
    (West/East) sides in two bands — near master (indices 1–2) and toward
    the far end (indices 3–4) — and the sixth seat (index 5) sits opposite
    the master on the far (-Z, North) short edge. Each seat faces the
    center of the table. The master sits on the near short edge
    specifically so it lines up with the volumetric window's own default
    viewing position and this view's ornament (see `GameSetup`'s
    own doc for why — without an active SharePlay session, nothing else
    rotates the table to face whichever seat is claimed).
    `assignSeatsForSharePlay` claims seats 1...4 in this array's order, so
    joining players fill West-then-East, near-band-then-far-band, exactly
    matching the order below. Every short-edge/long-side seat still sits a
    full table-length/-width beyond the table center along its own axis —
    same "well beyond the physical edge, the way a chair sits beyond a real
    table's edge" ratio the original layout used (see `diceLayout`'s doc
    for the matching dice-side reasoning). */
    @MainActor static let seatPoses: [TableVisualState.Pose2D] = [
        // Master — South (near, +Z) short edge, centered.
        .init(position: .init(x: 0, z: Double(GameMetrics.tableLength)), rotation: .degrees(0)),
        // West side, near band (close to master/South).
        .init(position: .init(x: -Double(GameMetrics.tableWidth), z: 0.5), rotation: .degrees(270)),
        // East side, near band (close to master/South).
        .init(position: .init(x: Double(GameMetrics.tableWidth), z: 0.5), rotation: .degrees(90)),
        // West side, far band (toward North).
        .init(position: .init(x: -Double(GameMetrics.tableWidth), z: -0.5), rotation: .degrees(270)),
        // East side, far band (toward North).
        .init(position: .init(x: Double(GameMetrics.tableWidth), z: -0.5), rotation: .degrees(90)),
        // North (far, -Z) short edge — the guest seat, see `guestSeat`.
        .init(position: .init(x: 0, z: -Double(GameMetrics.tableLength)), rotation: .degrees(180))
    ]

    /// The seat opposite the game master: the last of `seatPoses`. No device claims it; it is
    /// where the dice of the players without a table of their own are shown.
    @MainActor static var guestSeat: TableSeatIdentifier { TableSeatIdentifier(seatPoses.count - 1) }
    /// The first seat of a player: the near west seat, right of the master's seat 0.
    static let firstPlayerSeat = TableSeatIdentifier(1)
    /// The seats Vision Pro players are assigned to: all but the master's and the guest seat.
    @MainActor static var playerSeatCount: Int { seatPoses.count - 2 }

    init(id: TableSeatIdentifier, pose: TableVisualState.Pose2D) {
        self.id = id
        let spatialSeatPose: TableVisualState.Pose2D = .init(position: pose.position,
                                                             rotation: pose.rotation)
        initialState = .init(pose: spatialSeatPose)
    }

    /// `count` table-plane poses in the given seat's own player area — for that seat's own
    /// dice, sized to however many `GameTableModel.applyDiceRoll` currently needs visible (see
    /// `GameSetup.maxDicePerType`), not the full pre-allocated pool. In order from the seated
    /// player's left to their right; see `TableSeatDice.positions` for the layout itself.
    @MainActor
    static func diceLayout(inFrontOf seatPose: TableVisualState.Pose2D, count: Int) -> [TableVisualState.Pose2D] {
        TableSeatDice.positions(
            seatPosition: (seatPose.position.x, seatPose.position.z),
            rotation: seatPose.rotation.radians,
            count: count
        ).map { .init(position: .init(x: $0.x, z: $0.z), rotation: .zero) }
    }
}
#endif
