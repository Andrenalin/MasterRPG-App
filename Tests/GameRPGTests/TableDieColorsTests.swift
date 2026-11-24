// @copyright André Trettin

#if (os(iOS) || os(macOS) || os(visionOS)) && canImport(Testing)
import Foundation
import Testing

@testable import GameRPG

@Suite("Colors of the d6 on the 3D table")
struct TableDieColorsTests {
    @Test("Each d6 slot gets the color of the die of the set that lies in it")
    func slotsFollowTheSet() {
        let colors = TableDieColors.slots(
            dice: [
                (sides: 6, colorCode: "A"),
                (sides: 20, colorCode: "C"),
                (sides: 6, colorCode: "I"),
                (sides: 6, colorCode: "B")
            ],
            poolSize: 6
        )

        // The d20 has a slot of its own pool, so the d6s are numbered among themselves.
        #expect(colors == [.d6: [0: "A", 1: "I", 2: "B"], .d20: [0: "C"]])
    }

    @Test("Dice the table has no mesh for, or no free slot for, get no color")
    func unsupportedAndOverflowingDiceAreLeftOut() {
        let colors = TableDieColors.slots(
            dice: [(sides: 100, colorCode: "A"), (sides: 6, colorCode: "E"), (sides: 6, colorCode: "F"), (sides: 6, colorCode: "G")],
            poolSize: 2
        )

        #expect(colors == [.d6: [0: "E", 1: "F"]])
    }

    @Test("The d6, d8 and d20 are colored per kind, each numbered among its own kind")
    func kindsAreColoredApart() {
        let colors = TableDieColors.slots(
            dice: [
                (sides: 8, colorCode: "E"),
                (sides: 6, colorCode: "A"),
                (sides: 20, colorCode: "C"),
                (sides: 8, colorCode: "H")
            ],
            poolSize: 6
        )

        // `H` is a color of the d20 and d6 but not of the d8: it is kept, and resolved when the material is made.
        #expect(colors == [.d8: [0: "E", 1: "H"], .d6: [0: "A"], .d20: [0: "C"]])
        #expect(TableDieColors.isColored(.d20))
    }

    @Test("A seat nobody has rolled at yet still gets the fallback color, a known seat keeps its own")
    func unknownSeatsGetTheFallback() {
        var colors = TableDieColors()
        colors.set([.d6: [0: "A", 1: "B"]], seat: 1)

        colors.fillUnknown(seats: [0, 1], poolSize: 6)

        #expect(colors.slots[.d6]?[1] == [0: "A", 1: "B"])
        #expect(colors.slots[.d6]?[0]?.count == 6)
        #expect(colors.slots[.d6]?[0]?.values.allSatisfy { $0 == TableDiePalette.fallbackCode } == true)
        // The kinds the seat has no set for are filled too: the dice are there before any roll.
        #expect(colors.slots[.d20]?[1]?.count == 6)
    }

    @Test("Seat colors are kept per kind and seat")
    func setKeepsSeatsApart() {
        var colors = TableDieColors()
        colors.set([.d8: [0: "A"], .d6: [0: "B"]], seat: 1)
        colors.set([.d8: [0: "E"]], seat: 2)

        #expect(colors.slots[.d8] == [1: [0: "A"], 2: [0: "E"]])
        #expect(colors.slots[.d6] == [1: [0: "B"]])
    }

    @Test("A guest's d6 keep their color through the guest seat's slots")
    func guestColorsReachTheSlots() {
        let groups = TableGuestDice.groups(
            for: [
                TableGuestRoll(name: "Anna", dice: [
                    .init(kind: .d20, value: 17, colorCode: "D"),
                    .init(kind: .d6, value: 6, colorCode: "E")
                ]),
                TableGuestRoll(name: "Ben", dice: [.init(kind: .d6, value: 3, colorCode: "H")])
            ],
            poolSize: 6
        )

        #expect(groups[0].dice.last?.colorCode == "E")
        #expect(groups[1].dice == [.init(kind: .d6, slot: 1, value: 3, colorCode: "H")])
    }

    @Test("Every color code of a kind has its own palette, and an unknown one falls back to the green die")
    func palettes() {
        for kind in TableDieKind.allCases {
            let codes = TableDiePalette.codes(for: kind)
            let palettes = codes.map { TableDiePalette.palette(for: $0, kind: kind) }
            #expect(!codes.isEmpty)
            #expect(Set(palettes.map(\.body.red)).count > 1)
            for palette in palettes {
                #expect(palette.body != palette.pip)
            }
            #expect(TableDiePalette.palette(for: "Random", kind: kind) == TableDiePalette.palette(for: TableDiePalette.fallbackCode, kind: kind))
            // `G` is a code of its own too, not only the fallback.
            #expect(codes.contains(TableDiePalette.fallbackCode))
        }
    }

    @Test("A code means each kind's own color: the d8's C is a purple-blue die, not the green fallback")
    func codesAreKindSpecific() {
        #expect(TableDiePalette.palette(for: "C", kind: .d8) != TableDiePalette.palette(for: TableDiePalette.fallbackCode, kind: .d8))
        #expect(TableDiePalette.palette(for: "A", kind: .d6) != TableDiePalette.palette(for: "A", kind: .d8))
        #expect(TableDiePalette.resolvedCode("H", for: .d8) == TableDiePalette.fallbackCode)
        #expect(TableDiePalette.resolvedCode("H", for: .d6) == "H")
    }

    @Test("The d20 has its eight color codes, and a code means a different color than on the d6")
    func d20IsColored() {
        #expect(TableDiePalette.codes(for: .d20) == ["A", "B", "C", "D", "E", "F", "G", "H"])
        #expect(TableDiePalette.resolvedCode("I", for: .d20) == TableDiePalette.fallbackCode)
        #expect(TableDiePalette.palette(for: "D", kind: .d20) != TableDiePalette.palette(for: "D", kind: .d6))
    }

    @Test("The d3 has its five color codes, and is colored in a pool of its own")
    func d3IsColored() {
        #expect(TableDiePalette.codes(for: .d3) == ["A", "B", "C", "D", "G"])
        #expect(TableDiePalette.resolvedCode("E", for: .d3) == TableDiePalette.fallbackCode)
        let colors = TableDieColors.slots(
            dice: [(sides: 3, colorCode: "D"), (sides: 4, colorCode: "A"), (sides: 3, colorCode: "B")],
            poolSize: 6
        )

        #expect(colors == [.d3: [0: "D", 1: "B"], .d4: [0: "A"]])
    }

    @Test("The d4 has its six color codes, and is colored in a pool of its own")
    func d4IsColored() {
        #expect(TableDiePalette.codes(for: .d4) == ["A", "B", "C", "D", "E", "G"])
        #expect(TableDiePalette.resolvedCode("F", for: .d4) == TableDiePalette.fallbackCode)
        let colors = TableDieColors.slots(
            dice: [(sides: 4, colorCode: "E"), (sides: 6, colorCode: "A"), (sides: 4, colorCode: "C")],
            poolSize: 6
        )

        #expect(colors == [.d4: [0: "E", 1: "C"], .d6: [0: "A"]])
    }

    @Test("The d12 has its five color codes, and is colored in a pool of its own")
    func d12IsColored() {
        #expect(TableDiePalette.codes(for: .d12) == ["A", "B", "C", "D", "G"])
        #expect(TableDiePalette.resolvedCode("E", for: .d12) == TableDiePalette.fallbackCode)
        let colors = TableDieColors.slots(
            dice: [(sides: 12, colorCode: "C"), (sides: 10, colorCode: "A"), (sides: 12, colorCode: "D")],
            poolSize: 6
        )

        #expect(colors == [.d12: [0: "C", 1: "D"], .d10: [0: "A"]])
    }

    @Test("The d10 is colored like the d6 and d8, in a pool of its own")
    func d10IsColored() {
        let colors = TableDieColors.slots(
            dice: [(sides: 10, colorCode: "D"), (sides: 6, colorCode: "A"), (sides: 10, colorCode: "E")],
            poolSize: 6
        )

        #expect(colors == [.d10: [0: "D", 1: "E"], .d6: [0: "A"]])
    }
}
#endif
