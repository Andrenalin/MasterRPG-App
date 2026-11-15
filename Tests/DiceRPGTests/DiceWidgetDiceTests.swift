// @copyright André Trettin

import Foundation
import Testing

@testable import DiceRPG

/// CODE_AUDIT_26 §5.48: the widget draws a die only for a single-die roll.
@Suite("Dice widget dice")
struct DiceWidgetDiceTests {
    @Test("A multi-dice roll is named by its notation and is not a single die")
    func multiDiceRollIsNamedByNotation() {
        let snapshot = DiceSnapshot(
            id: UUID(),
            dice: [.die(sides: 6), .die(sides: 6), .die(sides: 6)]
        )

        let dice = DiceWidgetDice(snapshot)

        #expect(dice.name == "3D6")
        #expect(dice.dieCount == 3)
        #expect(!dice.isSingleDie)
    }

    @Test("A single die keeps its image")
    func singleDieIsDrawn() {
        let snapshot = DiceSnapshot(id: UUID(), dice: [.die(sides: 20)])

        let dice = DiceWidgetDice(snapshot)

        #expect(dice.name == "D20")
        #expect(dice.isSingleDie)
    }

    @Test("A name set by the person is kept")
    func namedRollKeepsItsName() {
        let snapshot = DiceSnapshot(id: UUID(), name: "Attack", dice: [.die(sides: 6), .die(sides: 6)])

        #expect(DiceWidgetDice(snapshot).name == "Attack")
    }

    @Test("Data saved before the die count existed reads as a single die")
    func olderDataIsSingleDie() {
        let dice = DiceWidgetDice(id: UUID(), name: "D6", sides: 6)

        #expect(dice.dieCount == nil)
        #expect(dice.isSingleDie)
    }
}
