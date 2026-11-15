// @copyright André Trettin

import CoreRPG
import Foundation
import Testing

@testable import DiceRPG

/// CODE_AUDIT_26 §10.17: the dice-set limit, and the bounded results (the editor clamp is in CoreRPGTests).
@MainActor
@Suite("Dice risks")
struct DiceRiskTests {
    @Test("A dice set refuses another die at the decode limit")
    func addDieIsRefusedAtTheLimit() async {
        let root = DiceRootModel.testRoot()
        await root.itemController.resetData()
        let itemId = UUID()
        let full = (0..<DiceModel.maximumDecodedDiceCount).map { _ in DieModel(id: UUID(), die: .six) }
        root.itemController.replace(model: DiceModel(id: itemId, name: "Full", dice: full), isInsert: true)

        let added = root.editController.add(die: DieModel(id: UUID(), die: .twenty), itemId: itemId)

        #expect(added == false)
        #expect(root.itemController.itemOrEmpty(for: itemId).dice.count == DiceModel.maximumDecodedDiceCount)
    }

    @Test("A die below the limit is added")
    func addDieBelowTheLimit() async {
        let root = DiceRootModel.testRoot()
        await root.itemController.resetData()
        let itemId = UUID()
        root.itemController.replace(model: DiceModel(id: itemId, name: "Bag", dice: []), isInsert: true)

        #expect(root.editController.add(die: DieModel(id: UUID(), die: .six), itemId: itemId))
        #expect(root.itemController.itemOrEmpty(for: itemId).dice.count == 1)
    }

    @Test("Bounding the results keeps the newest ones")
    func boundedResultsKeepTheLastResults() {
        let overflow = DieModel.maximumResultCount + 5
        let results = Array(1...overflow).map { $0 % 6 + 1 }

        let bounded = DieModel.boundedResults(results, die: RawDie(text: "d6"))

        #expect(bounded.count == DieModel.maximumResultCount)
        #expect(bounded == Array(results.suffix(DieModel.maximumResultCount)))
        #expect(bounded.last == results.last)
    }

    @Test("One more roll on a full die still shows the new result")
    func rollOnAFullDieIsVisible() {
        let full = Array(repeating: 1, count: DieModel.maximumResultCount)

        let bounded = DieModel.boundedResults(full + [6], die: RawDie(text: "d6"))

        #expect(bounded.last == 6)
        #expect(bounded.count == DieModel.maximumResultCount)
    }
}
