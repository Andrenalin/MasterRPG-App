// @copyright André Trettin

#if os(iOS) || os(macOS) || os(visionOS)
import Foundation

// The dice of the players without a table of their own (anyone not on Vision Pro), shown at the
// table's guest seat, opposite the game master. Pure, so it is unit-tested on iOS: every device
// derives the same groups from the same shared rolls, which lets one device place the dice and
// every device label them.

/// A guest's last shared roll, reduced to what the table has dice for: d20 and d6.
struct TableGuestRoll: Equatable {
    let name: String
    let d20: [Int]
    let d6: [Int]
}

enum TableGuestDice {
    /// One of a guest's dice on the table: a slot of the guest seat's d20 or d6 pool.
    struct Die: Equatable {
        let isD20: Bool
        let slot: Int
        let value: Int
    }

    /// A guest's dice on the table, lying together under one result popover.
    struct Group: Equatable {
        let name: String
        let dice: [Die]
    }

    /// Hands the guest seat's dice pool out to the guests, in the order of their names so the
    /// groups keep their places from roll to roll. The pool holds `poolSize` dice of each type;
    /// dice that no longer fit are left out, and so is a guest none of whose dice fit.
    static func groups(for rolls: [TableGuestRoll], poolSize: Int) -> [Group] {
        var nextD20 = 0
        var nextD6 = 0
        return rolls
            .sorted { ($0.name, $0.d20.count) < ($1.name, $1.d20.count) }
            .compactMap { roll in
                var dice: [Die] = []
                for value in roll.d20 where nextD20 < poolSize {
                    dice.append(Die(isD20: true, slot: nextD20, value: value))
                    nextD20 += 1
                }
                for value in roll.d6 where nextD6 < poolSize {
                    dice.append(Die(isD20: false, slot: nextD6, value: value))
                    nextD6 += 1
                }
                return dice.isEmpty ? nil : Group(name: roll.name, dice: dice)
            }
    }

    /// The positions on a row of dice, from one side of the table to the other.
    static var rowCapacity: Int {
        Int((usableWidth / spacing).rounded(.down)) + 1
    }

    /// Where the dice of groups of the given sizes lie, on the table plane: the groups side by
    /// side along the guest seat's edge, spread over its whole width, a group's dice together.
    /// Groups that do not fit on a row continue on the next one, further into the table; a
    /// group longer than a row is broken over several.
    static func positions(groupSizes: [Int]) -> [[(x: Double, z: Double)]] {
        // A row is a run of pieces: a group, or a row's worth of a group longer than a row.
        var rows: [[(group: Int, count: Int)]] = []
        var used = 0
        for (group, size) in groupSizes.enumerated() {
            var remaining = size
            while remaining > 0 {
                let count = min(remaining, rowCapacity)
                // A free position separates two pieces.
                let needed = count + (rows.last?.isEmpty == false ? 1 : 0)
                if rows.isEmpty || used + needed > rowCapacity {
                    rows.append([(group, count)])
                    used = count
                } else {
                    rows[rows.count - 1].append((group, count))
                    used += needed
                }
                remaining -= count
            }
        }

        var positions = [[(x: Double, z: Double)]](repeating: [], count: groupSizes.count)
        for (row, pieces) in rows.enumerated() {
            let z = -(Double(GameMetrics.tableLength) / 2 - Double(GameMetrics.diceEdgeInset)) + Double(row) * spacing
            let widths = pieces.map { Double($0.count - 1) * spacing }
            // The room the dice leave is shared out evenly: half a gap at each end.
            let gap = (usableWidth - widths.reduce(0, +)) / Double(pieces.count)
            var x = -usableWidth / 2 + gap / 2
            for (piece, width) in zip(pieces, widths) {
                positions[piece.group] += (0 ..< piece.count).map { (x + Double($0) * spacing, z) }
                x += width + gap
            }
        }
        return positions
    }

    /// The distance between neighboring dice; see `PlayerSeat.diceLayout`.
    static let spacing = 0.15
    /// The width a row's dice centers span: the table's, less the edge inset on both sides.
    private static var usableWidth: Double {
        Double(GameMetrics.tableWidth) - 2 * Double(GameMetrics.diceEdgeInset) - spacing
    }
}
#endif
