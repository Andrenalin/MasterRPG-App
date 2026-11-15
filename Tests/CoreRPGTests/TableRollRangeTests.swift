// @copyright André Trettin

#if canImport(Testing)
import Testing

@testable import CoreRPG

/// CODE_AUDIT_26 §5.2: "00" is the d100 maximum, and only ASCII digits are selector numbers.
struct TableRollRangeTests {
    @Test(arguments: [
        ("1-5", 1...5),
        ("7", 7...7),
        ("96-00", 96...100),
        ("00", 100...100),
        ("000", 1000...1000),
        ("00-09", 0...9),
        ("0", 0...0),
        ("5 – 10", 5...10),
        ("5—10", 5...10),
        ("*12*", 12...12),
        ("10-5", 5...10),
        ("97-00 A dragon", 97...100),
    ])
    func parses(name: String, expected: ClosedRange<Int>) {
        #expect(TableRollRange.selectorRange(for: name) == expected)
    }

    @Test func rolls97To100MatchTheLastRow() {
        let range = TableRollRange.selectorRange(for: "96-00")
        for roll in 96...100 { #expect(range?.contains(roll) == true) }
        #expect(range?.contains(95) == false)
    }

    @Test(arguments: ["½", "²", "Dragon", ""])
    func nonASCIIOrNoNumberIsNoSelector(name: String) {
        #expect(TableRollRange.selectorRange(for: name) == nil)
    }
}
#endif
