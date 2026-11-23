// @copyright André Trettin

#if os(iOS) || os(macOS) || os(visionOS)
import Foundation

// The dice of the players without a table of their own (anyone not on Vision Pro, the game
// master included). The others' dice are shown at the table's guest seat, opposite the game master's seat; the game master's own at the master's seat. Pure, so it is unit-tested on iOS: every device
// derives the same groups from the same shared rolls, which lets one device place the dice and
// every device label them.

/// A guest's last shared roll, reduced to what the table has dice for: d20, d12, d10, d8, d6, d4 and d3.
struct TableGuestRoll: Equatable {
    /// A rolled die of the set.
    struct Die: Equatable {
        let kind: TableDieKind
        let value: Int
        /// The die's colour code in the shared set, see `TableDieColors`.
        var colorCode = TableDiePalette.fallbackCode
    }

    let name: String
    /// In the order of the dice set, which is the order its result reads in.
    let dice: [Die]
    /// The game master's roll, whose result follows the master's dice sharing option.
    var isGameMaster = false
    /// The sender's id, the last sort key: two guests with the same name and dice count keep a
    /// stable order on every device. See CODE_AUDIT_26 §5.80.
    var senderId: UUID?
}

enum TableGuestDice {
    /// Separates the game master's roll from the other guests': the master's dice lie at the
    /// master's own seat on the near (south) edge, from a pool of their own, so no other guest's
    /// dice can take their slots; the others share the guest seat's pool.
    static func split(_ rolls: [TableGuestRoll]) -> (master: TableGuestRoll?, others: [TableGuestRoll]) {
        (rolls.first(where: \.isGameMaster), rolls.filter { !$0.isGameMaster })
    }

    /// One of a guest's dice on the table: a slot of the guest seat's d20 or d6 pool.
    struct Die: Equatable {
        let kind: TableDieKind
        let slot: Int
        let value: Int
        var colorCode = TableDiePalette.fallbackCode

    }

    /// A guest's dice on the table, lying together under one result popover.
    struct Group: Equatable {
        let name: String
        let dice: [Die]
        var isGameMaster = false
    }

    /// Hands the guest seat's dice pool out to the guests, in the order of their names so the
    /// groups keep their places from roll to roll. The pool holds `poolSize` dice of each type;
    /// dice that no longer fit are left out, and so is a guest none of whose dice fit.
    static func groups(for rolls: [TableGuestRoll], poolSize: Int) -> [Group] {
        var next: [TableDieKind: Int] = [:]
        return rolls
            .sorted { ($0.name, $0.dice.count, $0.senderId?.uuidString ?? "") < ($1.name, $1.dice.count, $1.senderId?.uuidString ?? "") }
            .compactMap { roll in
                // A group's dice lie in the order of the roll, the kinds mixed as the set has them.
                var dice: [Die] = []
                for die in roll.dice where next[die.kind, default: 0] < poolSize {
                    let slot = next[die.kind, default: 0]
                    dice.append(Die(kind: die.kind, slot: slot, value: die.value, colorCode: die.colorCode))
                    next[die.kind] = slot + 1
                }
                return dice.isEmpty ? nil : Group(name: roll.name, dice: dice, isGameMaster: roll.isGameMaster)
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

    /// The distance between neighboring dice.
    static let spacing = TableSeatDice.spacing
    /// The width a row's dice centers span: the table's, less the edge inset on both sides.
    private static var usableWidth: Double {
        Double(GameMetrics.tableWidth) - 2 * Double(GameMetrics.diceEdgeInset) - spacing
    }
}
#endif
