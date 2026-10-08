// @copyright André Trettin

import Foundation
import Testing

@testable import DiceRPG

/// CODE_AUDIT_15 §5.11: dice notation can come from imported or peer text.
@Suite("Dice notation limits")
struct RawDiceLimitsTests {
    @Test("A huge or negative-huge count is clamped instead of looping forever or trapping")
    func countIsClamped() {
        #expect(RawDieCounter(text: "999999999999d6").count == RawDieCounter.maximumCount)
        #expect(RawDieCounter(text: "-999999999999d6").count == -RawDieCounter.maximumCount)
    }

    // CODE_AUDIT_21 §5.24: the side count was bounded only when decoded.
    @Test("A die built from text has the same side limit as a decoded one")
    func sidesFromTextAreClamped() {
        let die = RawDie(text: "d9223372036854775807")
        #expect(die.max == 1_000_000)
        #expect((1...1_000_000).contains(die.roll()))
        // The reroll loop computes `max + 1`.
        #expect(DieModel(id: UUID(), die: die).roll(rerollOptions: []).result.count == 1)
        #expect(RawDie(.number(Int.max)).max == 1_000_000)
        #expect(RawDie(text: "d20").max == 20)
    }

    @Test("Saturating arithmetic never traps")
    func saturation() {
        #expect(Int.max.saturatingProduct(2) == Int.max)
        #expect(Int.min.saturatingProduct(2) == Int.min)
        #expect(Int.max.saturatingSum(1) == Int.max)
        #expect(Int.min.saturatingSum(-1) == Int.min)
        #expect(3.saturatingProduct(4) == 12)
        #expect(3.saturatingSum(4) == 7)
    }

    @Test("Ordinary notation is unchanged")
    func ordinaryNotation() {
        let counter = RawDieCounter(text: "2d6")
        #expect(counter.count == 2)
        #expect(counter.min == 2)
        #expect(counter.max == 12)
    }

    /// CODE_AUDIT_16 §5.4 / §5.5.
    @Test("Double-to-Int conversion saturates instead of trapping")
    func doubleSaturation() {
        #expect(Double.greatestFiniteMagnitude.saturatingInt == Int.max)
        #expect((-Double.greatestFiniteMagnitude).saturatingInt == Int.min)
        #expect(Double.nan.saturatingInt == 0)
        #expect(Double.infinity.saturatingInt == Int.max)
        #expect(12.9.saturatingInt == 12)
    }

    @Test("Modifier text and dice merging never overflow")
    func textArithmeticSaturates() {
        let dice = RawDice(text: "+9223372036854775807+1")
        #expect(dice.modifier == Int.max)
        var merged = RawDice(dieCounter: RawDieCounter(die: .six, count: Int.max))
        merged.addDie(RawDieCounter(die: .six, count: 1))
        #expect(merged.max == Int.max)
    }
}
