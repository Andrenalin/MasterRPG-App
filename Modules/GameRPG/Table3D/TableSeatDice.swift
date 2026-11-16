// @copyright André Trettin

#if os(iOS) || os(macOS) || os(visionOS)
import Foundation

// Which of a seat's pool dice stand for a dice set, and where they lie. Pure, so it is
// unit-tested on iOS: the row on the table has to read like the set's result, left to right
// for the player at that seat.

/// The die types the table has a mesh and a pool for.
enum TableDieKind: Hashable, CaseIterable {
    case d20
    case d12
    case d10
    case d8
    case d6
    case d4
    case d3

    /// The kind of a die with this many sides, `nil` if the table has no mesh for it.
    /// Takes the *resolved* side count (`RawDie.max`), not the `Sides` enum case: a die authored
    /// through the sheet's UI can end up as `.number(20)` instead of `.twenty`, and those don't
    /// compare equal despite meaning the same die.
    init?(sides: Int) {
        switch sides {
            case 20: self = .d20
            case 12: self = .d12
            case 10: self = .d10
            case 8: self = .d8
            case 6: self = .d6
            case 4: self = .d4
            case 3: self = .d3
            default: return nil
        }
    }

    var sides: Int {
        switch self {
            case .d20: 20
            case .d12: 12
            case .d10: 10
            case .d8: 8
            case .d6: 6
            case .d4: 4
            case .d3: 3
        }
    }
}

enum TableSeatDice {
    /// A die of a dice set on the table: a slot of the seat's pool of its kind.
    struct Slot: Equatable {
        let kind: TableDieKind
        let slot: Int
        /// The die's place in the dice set.
        let index: Int

    }

    /// Hands a seat's pool out to the dice of a set, in the set's own order — the order of the
    /// returned slots is the order the dice lie in. The pool holds `poolSize` dice of each type;
    /// dice it has no mesh or no free slot for are left out.
    static func slots(sides: [Int], poolSize: Int) -> [Slot] {
        var next: [TableDieKind: Int] = [:]
        return sides.enumerated().compactMap { index, sides in
            guard let kind = TableDieKind(sides: sides), next[kind, default: 0] < poolSize else { return nil }
            let slot = next[kind, default: 0]
            next[kind] = slot + 1
            return Slot(kind: kind, slot: slot, index: index)
        }
    }

    /// `count` table-plane positions in a seat's own player area, laid out side by side and
    /// centered on the seat itself, from the seated player's left to their right.
    ///
    /// Derived from the seat's own facing `rotation`, not a radius along its
    /// raw `position` (the original single-seat-per-side approach): with two
    /// seats sharing a long side (see `PlayerSeat.seatPoses`), both share the same
    /// facing direction but sit at different lateral offsets, so the row
    /// needs to be centered under *this* seat's own position, not the
    /// table's. `direction` (the seat's own outward-facing axis) locates
    /// that near table edge — inset by `GameMetrics.diceEdgeInset` so the
    /// dice land just inside the table's physical edge rather than off the
    /// surface, the way a chair sits beyond that edge. `lateralOffset`
    /// re-centers the row under the seat's actual lateral position along
    /// that edge.
    static func positions(
        seatPosition: (x: Double, z: Double),
        rotation radians: Double,
        count: Int
    ) -> [(x: Double, z: Double)] {
        guard count > 0 else { return [] }
        // The direction a seat at this rotation faces *away* from the table
        // center — e.g. a north-side seat (rotation 0°, facing into the
        // table) points further north. Dice sit between the seat and the
        // center, along this same axis. See `PlayerSeat.seatPoses`'s doc for
        // why rotation 0° maps to +Z here.
        let direction: (x: Double, z: Double) = (sin(radians), cos(radians))
        // Perpendicular to `direction`, to spread the dice apart and to
        // locate the seat's own lateral position along its edge. It points to
        // the seated player's right (they look along `-direction`), so the
        // first die of a set is the leftmost one for them. It used to point
        // left, which laid a result of "11 | 3" out as 3, 11.
        let lateral: (x: Double, z: Double) = (direction.z, -direction.x)

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
        let lateralOffset = seatPosition.x * lateral.x + seatPosition.z * lateral.z

        let totalWidth = spacing * Double(count - 1)
        return (0 ..< count).map { index in
            let offset = lateralOffset + Double(index) * spacing - totalWidth / 2
            return (
                x: direction.x * radius + lateral.x * offset,
                z: direction.z * radius + lateral.z * offset
            )
        }
    }

    /// Distance between neighboring dice, center to center. It used to be 0.15 m, sized for a
    /// 7.5 cm d20 that TabletopKit otherwise resolved by resting one die on top of the other
    /// (0.05 m and 0.11 m overlapped). Every die is now 3 to 3.75 cm tall, so it is halved to
    /// 0.075 m: at least two die widths for the widest, the d20.
    static let spacing = 0.075
}
#endif
