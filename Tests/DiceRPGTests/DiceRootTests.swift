// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import DiceRPG

@MainActor
struct DiceRootTests {
    @Test func importer() async throws {
        let sut = DiceRootModel.testRoot()
        await sut.itemController.resetData()
        
        let dice = DiceModel(
            id: UUID(),
            name: "TestName",
            description: "Hello something",
            tags: ["DS", "Good"],
            category: .table,
            displayState: 3,
            dice: [DieModel(id: UUID(), die: .twenty)],
            sumUp: true,
            modifier: 0,
            percentDice: false,
            compareOption: DiceModel.CompareValue.lowerEqual,
            compareValue: 44,
            coupValues: [DiceModel.CoupFumbleOption.diceValue(1)],
            coupOnlyOnFirstDie: false,
            fumbleValues: [DiceModel.CoupFumbleOption.diceValue(20)],
            fumbleOnlyOnFirstDie: true,
            rerollOptions: [DiceModel.RerollOption(number: 1, value: 0, maxDiceValue: true)],
            reorderDice: true,
            addDiceEvery: 20,
            resultCategory: ResultCategory(id: UUID(), module: .table)
        )

        sut.itemController.replace(model: dice, isInsert: true)

        #expect(sut.itemController.itemDataModel.items.count == 1)
        
        await sut.gameController.focus(on: dice.id)
        #expect(sut.gameController.isFocusedDice(itemId: dice.id))
        
        sut.editController.remove(die: dice.dice[0], itemId: dice.id)
        #expect(await sut.itemController.item(for: dice.id)?.dice.count == 0)
    }
}
#endif
