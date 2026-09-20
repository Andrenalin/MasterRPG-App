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
    viewing position and this view's ornaments/dice-bar (see `GameSetup`'s
    own doc for why — without an active SharePlay session, nothing else
    rotates the table to face whichever seat is claimed).
    `assignSeatsForSharePlay` claims seats 1...5 in this array's order, so
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
        // North (far, -Z) short edge — the sixth seat.
        .init(position: .init(x: 0, z: -Double(GameMetrics.tableLength)), rotation: .degrees(180))
    ]

    init(id: TableSeatIdentifier, pose: TableVisualState.Pose2D) {
        self.id = id
        let spatialSeatPose: TableVisualState.Pose2D = .init(position: pose.position,
                                                             rotation: pose.rotation)
        initialState = .init(pose: spatialSeatPose)
    }

    /// `count` table-plane positions in the given seat's own player area,
    /// laid out side by side and centered on the seat itself — for that
    /// seat's own dice, sized to however many `GameTableModel.applyDiceRoll`
    /// currently needs visible (see `GameSetup.maxDicePerType`), not the
    /// full pre-allocated pool.
    ///
    /// Derived from the seat's own facing `rotation`, not a radius along its
    /// raw `position` (the original single-seat-per-side approach): with two
    /// seats sharing a long side (see `seatPoses`), both share the same
    /// facing direction but sit at different lateral offsets, so the row
    /// needs to be centered under *this* seat's own position, not the
    /// table's. `direction` (the seat's own outward-facing axis) locates
    /// that near table edge — inset by `GameMetrics.diceEdgeInset` so the
    /// dice land just inside the table's physical edge rather than off the
    /// surface, the way a chair sits beyond that edge. `lateralOffset`
    /// re-centers the row under the seat's actual lateral position along
    /// that edge.
    @MainActor
    static func diceLayout(inFrontOf seatPose: TableVisualState.Pose2D, count: Int) -> [TableVisualState.Pose2D] {
        guard count > 0 else { return [] }
        let radians = seatPose.rotation.radians
        // The direction a seat at this rotation faces *away* from the table
        // center — e.g. a north-side seat (rotation 0°, facing into the
        // table) points further north. Dice sit between the seat and the
        // center, along this same axis. See `PlayerSeat.seatPoses`'s doc for
        // why rotation 0° maps to +Z here.
        let direction: (x: Double, z: Double) = (sin(radians), cos(radians))
        // Perpendicular to `direction`, to spread the dice apart and to
        // locate the seat's own lateral position along its edge.
        let lateral: (x: Double, z: Double) = (-direction.z, direction.x)

        // The seat's near table edge along its own facing axis. `direction`
        // is always axis-aligned (a multiple of 90°), so exactly one term is
        // non-zero — this picks `tableWidth` (X is the short axis now) for
        // the West/East long-side seats, and `tableLength` (Z is the long
        // axis now) for the South/North short-edge seats, automatically.
        let halfExtent = abs(direction.x) * Double(GameMetrics.tableWidth / 2)
            + abs(direction.z) * Double(GameMetrics.tableLength / 2)
        let radius = halfExtent - Double(GameMetrics.diceEdgeInset)

        // This seat's own position along the lateral axis — 0 for the
        // single end seats (which sit exactly on `direction`'s own axis),
        // non-zero for a long-side seat sharing that side with another.
        let seatPosition = seatPose.position
        let lateralOffset = seatPosition.x * lateral.x + seatPosition.z * lateral.z

        // Distance between neighboring dice, center to center. This was
        // shrunk from the original 2-die-only layout's 0.14 m to 0.05 m to
        // keep a seat's row compact at `maxDicePerType`'s largest realistic
        // mixes, but never re-checked against the die's own physical size —
        // at 0.05 m, two ~0.075 m-wide D20s (see `Die20`'s own
        // `representation`) overlap enough that TabletopKit resolves it by
        // resting one on top of the other instead of side by side. 0.11 m
        // (tried first, aiming for the "half a die's width" gap this method
        // was originally asked for) still left a partial, roughly
        // half-die-height overlap — the die's true collision size needs
        // closer to that original 0.14 m after all. 0.15 m stays a hair
        // above it for margin, since the previous, closer-but-still-short
        // guess undershot.
        let spacing = 0.15
        let totalWidth = spacing * Double(count - 1)

        return (0 ..< count).map { index in
            let offset = lateralOffset + Double(index) * spacing - totalWidth / 2
            return TableVisualState.Pose2D(
                position: .init(
                    x: direction.x * radius + lateral.x * offset,
                    z: direction.z * radius + lateral.z * offset
                ),
                rotation: .zero
            )
        }
    }
}
#endif
