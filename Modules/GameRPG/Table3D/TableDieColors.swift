// @copyright André Trettin

#if os(iOS) || os(macOS) || os(visionOS)
import Foundation

// The colour of every die on the 3D table. A die's colour is the one its dice set has (`DieModel`'s
// colour code), so every device works it out from the sets it already knows — its own focused
// set, the shared sets of the other players, a guest's shared roll — and nothing new is synced.
// Pure, so it is unit-tested on iOS.

/// The body and pip (or numeral) colour of one colour code of a die kind, sRGB 0…1. Each kind
/// has the codes its 2D art (`D6<code>-<face>`, `D8<code>-…`, `D10<code>-…`) has, and a code is a
/// different dice colour for each kind, so the palette is taken from that kind's photographed dice.
struct TableDiePalette: Equatable {
    struct RGB: Equatable {
        let red: Float
        let green: Float
        let blue: Float
    }

    let body: RGB
    let pip: RGB

    /// The code a die with an unknown or empty colour falls back to: the green one, as the
    /// model's own fallback does. Every kind with coloured art has a green `G`.
    static let fallbackCode = "G"

    /// The colour codes that have art for a die kind, see `RawDie.colorCodes`.
    static func codes(for kind: TableDieKind) -> [String] {
        switch kind {
            case .d6: ["A", "B", "E", "F", "G", "H", "I"]
            case .d8: ["A", "B", "C", "G"]
            case .d12: ["A", "B", "C", "D", "G"]
            case .d4: ["A", "B", "C", "D", "E", "G"]
            case .d3: ["A", "B", "C", "D", "G"]
            case .d10: ["A", "B", "C", "D", "E", "F", "G"]
            case .d20: ["A", "B", "C", "D", "E", "F", "G", "H"]
        }
    }

    /// The code itself if the kind has art for it, else the fallback.
    static func resolvedCode(_ code: String, for kind: TableDieKind) -> String {
        codes(for: kind).contains(code) ? code : fallbackCode
    }

    private static func make(_ body: (Float, Float, Float), _ pip: (Float, Float, Float)) -> TableDiePalette {
        TableDiePalette(
            body: .init(red: body.0, green: body.1, blue: body.2),
            pip: .init(red: pip.0, green: pip.1, blue: pip.2)
        )
    }

    static func palette(for code: String, kind: TableDieKind) -> TableDiePalette {
        switch kind {
            case .d20:
                switch code {
                    case "A": make((0.62, 0.05, 0.07), (0.88, 0.80, 0.52))   // red
                    case "B": make((0.10, 0.17, 0.42), (0.88, 0.80, 0.55))   // navy pearl
                    case "C": make((0.22, 0.10, 0.38), (0.93, 0.93, 0.93))   // dark purple, white
                    case "D": make((0.90, 0.40, 0.06), (0.94, 0.93, 0.90))   // orange, white
                    case "E": make((0.90, 0.90, 0.89), (0.07, 0.07, 0.08))   // white, black numerals
                    case "F": make((0.40, 0.09, 0.45), (0.90, 0.64, 0.20))   // purple pearl, gold
                    case "H": make((0.10, 0.10, 0.12), (0.90, 0.64, 0.20))   // black pearl, gold
                    default: make((0.04, 0.50, 0.20), (0.96, 0.96, 0.94))    // green pearl
                }
            case .d6:
                switch code {
                    case "A": make((0.62, 0.05, 0.07), (0.86, 0.76, 0.46))   // red
                    case "B": make((0.09, 0.21, 0.40), (0.82, 0.74, 0.47))   // navy
                    case "E": make((0.35, 0.07, 0.38), (0.88, 0.68, 0.22))   // purple
                    case "F": make((0.12, 0.31, 0.46), (0.88, 0.85, 0.68))   // steel blue
                    case "H": make((0.05, 0.38, 0.45), (0.88, 0.62, 0.17))   // teal
                    case "I": make((0.14, 0.04, 0.05), (0.88, 0.68, 0.22))   // black-red
                    default: make((0.06, 0.45, 0.15), (0.94, 0.94, 0.90))    // green
                }
            case .d8:
                switch code {
                    case "A": make((0.55, 0.04, 0.06), (0.90, 0.86, 0.72))   // red
                    case "B": make((0.08, 0.17, 0.45), (0.88, 0.85, 0.74))   // navy
                    case "C": make((0.30, 0.20, 0.62), (0.86, 0.66, 0.26))   // purple-blue
                    default: make((0.06, 0.52, 0.18), (0.95, 0.95, 0.92))    // green
                }
            case .d3:
                switch code {
                    case "A": make((0.72, 0.08, 0.07), (0.96, 0.94, 0.91))   // red
                    case "B": make((0.10, 0.14, 0.45), (0.96, 0.94, 0.91))   // navy
                    case "C": make((0.50, 0.25, 0.78), (0.97, 0.96, 0.97))   // purple
                    case "D": make((0.94, 0.93, 0.86), (0.06, 0.06, 0.07))   // ivory, black numerals
                    default: make((0.05, 0.30, 0.12), (0.96, 0.96, 0.94))    // dark green
                }
            case .d4:
                switch code {
                    case "A": make((0.70, 0.11, 0.05), (0.88, 0.84, 0.72))   // red
                    case "B": make((0.12, 0.30, 0.55), (0.88, 0.85, 0.72))   // blue
                    case "C": make((0.07, 0.03, 0.12), (0.90, 0.90, 0.88))   // black-purple
                    case "D": make((0.50, 0.12, 0.50), (0.88, 0.68, 0.25))   // purple
                    case "E": make((0.86, 0.89, 0.91), (0.06, 0.06, 0.07))   // pearl white, black numerals
                    default: make((0.10, 0.62, 0.25), (0.95, 0.95, 0.92))    // green
                }
            case .d12:
                switch code {
                    case "A": make((0.58, 0.06, 0.08), (0.88, 0.84, 0.70))   // red
                    case "B": make((0.10, 0.20, 0.45), (0.88, 0.84, 0.66))   // navy pearl
                    case "C": make((0.10, 0.30, 0.50), (0.92, 0.93, 0.90))   // teal blue
                    case "D": make((0.35, 0.18, 0.55), (0.88, 0.68, 0.25))   // purple-blue
                    default: make((0.06, 0.50, 0.20), (0.95, 0.95, 0.92))    // green
                }
            case .d10:
                switch code {
                    case "A": make((0.60, 0.05, 0.07), (0.84, 0.74, 0.46))   // red
                    case "B": make((0.10, 0.25, 0.42), (0.82, 0.68, 0.35))   // steel blue
                    case "C": make((0.58, 0.06, 0.08), (0.88, 0.84, 0.68))   // red, tens
                    case "D": make((0.12, 0.25, 0.52), (0.82, 0.68, 0.35))   // blue, tens
                    case "E": make((0.36, 0.14, 0.55), (0.86, 0.66, 0.25))   // purple
                    case "F": make((0.28, 0.17, 0.55), (0.88, 0.66, 0.20))   // purple-blue, tens
                    default: make((0.06, 0.50, 0.17), (0.94, 0.94, 0.90))    // green
                }
        }
    }
}

/// The colour codes of every pool slot of the dice that are coloured, per seat.
struct TableDieColors: Equatable {
    /// Slot → colour code, by die kind and seat (`TableSeatIdentifier.rawValue`). A slot that no
    /// set of the seat uses has no entry, and keeps the colour it has: it lies parked off the table.
    var slots: [TableDieKind: [Int: [Int: String]]] = [:]

    /// Whether the table colours dice of this kind: every kind has art for its colors.
    static func isColored(_ kind: TableDieKind) -> Bool {
        !TableDiePalette.codes(for: kind).isEmpty
    }

    /// The colour of each slot of a seat for a dice set, given as the side count and colour code
    /// of each die in the set's order — the order `TableSeatDice.slots` hands the pool out in.
    static func slots(dice: [(sides: Int, colorCode: String)], poolSize: Int) -> [TableDieKind: [Int: String]] {
        var colors: [TableDieKind: [Int: String]] = [:]
        for slot in TableSeatDice.slots(sides: dice.map(\.sides), poolSize: poolSize) where isColored(slot.kind) {
            colors[slot.kind, default: [:]][slot.slot] = dice[slot.index].colorCode
        }
        return colors
    }

    /// Adds a seat's slot colours.
    mutating func set(_ colors: [TableDieKind: [Int: String]], seat: Int) {
        for (kind, slotColors) in colors {
            slots[kind, default: [:]][seat] = slotColors
        }
    }
}
#endif
