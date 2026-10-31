// @copyright André Trettin

import CoreRPG
import Testing

@testable import CharacterRPG

/// CODE_AUDIT_Since_3.0.1 §5.17: `Int(wanted.rounded())` trapped on extreme input from another
/// shortcut.
@Suite("Character value changes")
struct CharacterValueChangeTests {
    @Test("Changes apply to the current value")
    func apply() {
        #expect(CharacterValueChange.add.apply(3, to: 10) == 13)
        #expect(CharacterValueChange.subtract.apply(7, to: 10) == 3)
        #expect(CharacterValueChange.set.apply(4, to: 10) == 4)
    }

    @Test("A stored number is rounded and clamped instead of trapping")
    func storableNumber() {
        #expect(CharacterValueChange.storableNumber(2.5) == 3)
        #expect(CharacterValueChange.storableNumber(-2.4) == -2)
        #expect(CharacterValueChange.storableNumber(CharacterValueChange.add.apply(Double(Int.max), to: 10)) == SheetNumberLimit.maximumMagnitude)
        #expect(CharacterValueChange.storableNumber(CharacterValueChange.subtract.apply(Double(Int.max), to: -10)) == -SheetNumberLimit.maximumMagnitude)
        #expect(CharacterValueChange.storableNumber(.infinity) == SheetNumberLimit.maximumMagnitude)
        #expect(CharacterValueChange.storableNumber(-.infinity) == -SheetNumberLimit.maximumMagnitude)
        #expect(CharacterValueChange.storableNumber(.nan) == 0)
    }
}
