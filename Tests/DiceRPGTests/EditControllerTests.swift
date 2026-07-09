// @copyright André Trettin

import CoreRPG
import Foundation
import Testing

@testable import DiceRPG

@MainActor
struct EditControllerTests {
    @Test func diceOptionsCanBeAddedRemovedAndReset() async throws {
        let root = DiceRootModel.testRoot()
        await root.itemController.resetData()
        let sut = root.editController
        let itemId = UUID()
        let baseDie = DieModel(id: UUID(), die: .six)
        let extraDie = DieModel(id: UUID(), die: .twenty, result: [20])
        let dice = DiceModel(
            id: itemId,
            name: "Editable Dice",
            dice: [baseDie],
            coupOnlyOnFirstDie: true,
            fumbleOnlyOnFirstDie: true
        )
        root.itemController.replace(model: dice, isInsert: true)

        _ = sut.itemControllable
        _ = sut.fileUrlDataController
        _ = sut.linkRegisterController

        sut.add(die: extraDie, itemId: itemId)
        #expect(root.itemController.itemOrEmpty(for: itemId).dice.map(\.id) == [baseDie.id, extraDie.id])

        sut.remove(die: extraDie, itemId: itemId)
        #expect(root.itemController.itemOrEmpty(for: itemId).dice.map(\.id) == [baseDie.id])

        sut.add(coup: 20, isDiceValueCoup: true, itemId: itemId)
        sut.add(coup: 42, isDiceValueCoup: false, itemId: itemId)
        var edited = root.itemController.itemOrEmpty(for: itemId)
        #expect(edited.coupValues == [.diceValue(20), .result(42)])
        #expect(!edited.coupOnlyOnFirstDie)

        sut.remove(coup: .diceValue(20), itemId: itemId)
        edited = root.itemController.itemOrEmpty(for: itemId)
        #expect(edited.coupValues == [.result(42)])

        sut.add(fumble: 1, isDiceValueFumble: true, itemId: itemId)
        sut.add(fumble: 2, isDiceValueFumble: false, itemId: itemId)
        edited = root.itemController.itemOrEmpty(for: itemId)
        #expect(edited.fumbleValues == [.diceValue(1), .result(2)])
        #expect(!edited.fumbleOnlyOnFirstDie)

        sut.remove(fumble: .diceValue(1), itemId: itemId)
        edited = root.itemController.itemOrEmpty(for: itemId)
        #expect(edited.fumbleValues == [.result(2)])

        sut.add(reroll: 2, value: 5, isMaxDiceValue: true, itemId: itemId)
        let reroll = try #require(root.itemController.itemOrEmpty(for: itemId).rerollOptions.first)
        #expect(reroll.number == 2)
        #expect(reroll.value == 5)
        #expect(reroll.maxDiceValue)

        sut.remove(reroll: reroll, itemId: itemId)
        #expect(root.itemController.itemOrEmpty(for: itemId).rerollOptions.isEmpty)

        sut.reset(addValue: 3, itemId: itemId)
        sut.reset(compareValue: 12, itemId: itemId)
        sut.reset(modifer: -2, itemId: itemId)
        sut.reset(compareOption: .equalHigher, itemId: itemId)

        edited = root.itemController.itemOrEmpty(for: itemId)
        #expect(edited.addDiceEvery == 3)
        #expect(edited.compareValue == 12)
        #expect(edited.modifier == -2)
        #expect(edited.compareOption == .equalHigher)

        let missingId = UUID()
        sut.add(die: extraDie, itemId: missingId)
        sut.remove(die: extraDie, itemId: missingId)
        sut.add(coup: 1, isDiceValueCoup: true, itemId: missingId)
        sut.remove(coup: .result(42), itemId: missingId)
        sut.add(fumble: 1, isDiceValueFumble: true, itemId: missingId)
        sut.remove(fumble: .result(2), itemId: missingId)
        sut.add(reroll: 1, value: 1, isMaxDiceValue: false, itemId: missingId)
        sut.remove(reroll: DiceModel.RerollOption(number: 1, value: 1, maxDiceValue: false), itemId: missingId)
        sut.reset(addValue: 1, itemId: missingId)
        sut.reset(compareValue: 1, itemId: missingId)
        sut.reset(modifer: 1, itemId: missingId)
        sut.reset(compareOption: .off, itemId: missingId)
    }
}
