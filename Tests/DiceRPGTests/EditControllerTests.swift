// @copyright André Trettin

import CoreRPG
import Foundation
import Testing

@testable import DiceRPG

@MainActor
struct EditControllerTests {
    @Test func addingTheSameCatalogDieTwiceKeepsDistinctIds() async throws {
        let root = DiceRootModel.testRoot()
        await root.itemController.resetData()
        let sut = root.editController
        let itemId = UUID()
        let catalogDie = DieModel(id: UUID(), die: .twenty)
        root.itemController.replace(model: DiceModel(id: itemId, name: "Bag", dice: []), isInsert: true)

        sut.add(die: catalogDie, itemId: itemId, forceSave: false)
        sut.add(die: catalogDie, itemId: itemId, forceSave: false)

        let ids = root.itemController.itemOrEmpty(for: itemId).dice.map(\.id)
        #expect(ids.count == 2)
        #expect(Set(ids).count == 2)
        #expect(!ids.contains(catalogDie.id))
    }

    // CODE_AUDIT_28 §5.24
    @Test func sameOptionsAreNotAddedTwice() async throws {
        let root = DiceRootModel.testRoot()
        await root.itemController.resetData()
        let sut = root.editController
        let itemId = UUID()
        root.itemController.replace(model: DiceModel(id: itemId, name: "Bag", dice: [DieModel(id: UUID(), die: .twenty)]), isInsert: true)

        sut.add(coup: 20, isDiceValueCoup: true, itemId: itemId, forceSave: false)
        sut.add(coup: 20, isDiceValueCoup: true, itemId: itemId, forceSave: false)
        sut.add(fumble: 1, isDiceValueFumble: false, itemId: itemId, forceSave: false)
        sut.add(fumble: 1, isDiceValueFumble: false, itemId: itemId, forceSave: false)
        sut.add(reroll: 1, value: 3, isMaxDiceValue: false, itemId: itemId, forceSave: false)
        sut.add(reroll: 1, value: 4, isMaxDiceValue: true, itemId: itemId, forceSave: false)

        let item = root.itemController.itemOrEmpty(for: itemId)
        #expect(item.coupValues.count == 1)
        #expect(item.fumbleValues.count == 1)
        #expect(item.rerollOptions.count == 1)
        #expect(item.rerollOptions.first?.value == 4)
    }

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

        sut.add(die: extraDie, itemId: itemId, forceSave: false)
        let added = root.itemController.itemOrEmpty(for: itemId).dice
        #expect(added.count == 2)
        #expect(added.first?.id == baseDie.id)
        let addedDie = try #require(added.last)
        #expect(addedDie.id != extraDie.id)
        #expect(addedDie.die == extraDie.die)

        sut.remove(die: addedDie, itemId: itemId, forceSave: false)
        #expect(root.itemController.itemOrEmpty(for: itemId).dice.map(\.id) == [baseDie.id])

        sut.add(coup: 20, isDiceValueCoup: true, itemId: itemId, forceSave: false)
        sut.add(coup: 42, isDiceValueCoup: false, itemId: itemId, forceSave: false)
        var edited = root.itemController.itemOrEmpty(for: itemId)
        #expect(edited.coupValues == [.diceValue(20), .result(42)])
        #expect(!edited.coupOnlyOnFirstDie)

        sut.remove(coup: .diceValue(20), itemId: itemId, forceSave: false)
        edited = root.itemController.itemOrEmpty(for: itemId)
        #expect(edited.coupValues == [.result(42)])

        sut.add(fumble: 1, isDiceValueFumble: true, itemId: itemId, forceSave: false)
        sut.add(fumble: 2, isDiceValueFumble: false, itemId: itemId, forceSave: false)
        edited = root.itemController.itemOrEmpty(for: itemId)
        #expect(edited.fumbleValues == [.diceValue(1), .result(2)])
        #expect(!edited.fumbleOnlyOnFirstDie)

        sut.remove(fumble: .diceValue(1), itemId: itemId, forceSave: false)
        edited = root.itemController.itemOrEmpty(for: itemId)
        #expect(edited.fumbleValues == [.result(2)])

        sut.add(reroll: 2, value: 5, isMaxDiceValue: true, itemId: itemId, forceSave: false)
        let reroll = try #require(root.itemController.itemOrEmpty(for: itemId).rerollOptions.first)
        #expect(reroll.number == 2)
        #expect(reroll.value == 5)
        #expect(reroll.maxDiceValue)

        sut.remove(reroll: reroll, itemId: itemId, forceSave: false)
        #expect(root.itemController.itemOrEmpty(for: itemId).rerollOptions.isEmpty)

        sut.reset(addValue: 3, itemId: itemId, forceSave: false)
        sut.reset(compareValue: 12, itemId: itemId, forceSave: false)
        sut.reset(modifier: -2, itemId: itemId, forceSave: false)
        sut.reset(compareOption: .equalHigher, itemId: itemId, forceSave: false)

        edited = root.itemController.itemOrEmpty(for: itemId)
        #expect(edited.addDiceEvery == 3)
        #expect(edited.compareValue == 12)
        #expect(edited.modifier == -2)
        #expect(edited.compareOption == .equalHigher)

        let missingId = UUID()
        sut.add(die: extraDie, itemId: missingId, forceSave: false)
        sut.remove(die: extraDie, itemId: missingId, forceSave: false)
        sut.add(coup: 1, isDiceValueCoup: true, itemId: missingId, forceSave: false)
        sut.remove(coup: .result(42), itemId: missingId, forceSave: false)
        sut.add(fumble: 1, isDiceValueFumble: true, itemId: missingId, forceSave: false)
        sut.remove(fumble: .result(2), itemId: missingId, forceSave: false)
        sut.add(reroll: 1, value: 1, isMaxDiceValue: false, itemId: missingId, forceSave: false)
        sut.remove(reroll: DiceModel.RerollOption(number: 1, value: 1, maxDiceValue: false), itemId: missingId, forceSave: false)
        sut.reset(addValue: 1, itemId: missingId, forceSave: false)
        sut.reset(compareValue: 1, itemId: missingId, forceSave: false)
        sut.reset(modifier: 1, itemId: missingId, forceSave: false)
        sut.reset(compareOption: .off, itemId: missingId, forceSave: false)
    }
}
