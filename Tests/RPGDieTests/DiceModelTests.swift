// @copyright André Trettin

#if canImport(Testing)
import AndrenalinKit
import Foundation
import Testing

@testable import DiceRPG

struct DiceModelTests {
    func setUp() async throws -> DiceModel {
        DiceModel(
            id: UUID(),
            name: "TestName",
            description: "Hello something",
            tags: ["DS", "Good"],
            category: .table,
            displayState: 3,
            dice: [
                DieModel(id: UUID(), die: .twenty, rotation: 0, result: [], displayState: 3),
                DieModel(id: UUID(), die: .twenty, rotation: 0, result: [], displayState: 3),
                DieModel(id: UUID(), die: .twenty, rotation: 0, result: [], displayState: 3),
            ],
            sumUp: true,
            modifier: 0,
            percentDice: false,
            compareOption: DiceModel.CompareValue.lowerEqual,
            compareValue: 44,
            coupValues: [DiceModel.CoupFumbleOption.diceValue(1)],
            coupOnlyOnFirstDie: false,
            fumbleValues: [DiceModel.CoupFumbleOption.diceValue(20)],
            fumbleOnlyOnFirstDie: true,
            reroleOptions: [DiceModel.RerollOption(number: 1, value: 0, maxDiceValue: true)],
            reorderDice: true,
            addDiceEvery: 20,
            resultCategory: ResultCategory(id: UUID(), module: .table)
        )
    }

    @Test func assignAndDuplicate() async throws {
        let sut = try await setUp()
        let a = sut.copy()
        #expect(a == sut)

        let d = sut.duplicate()
        #expect(d.name == "\(a.name) Copy")
        #expect(d.description == sut.description)
        #expect(d.tags == sut.tags)
        #expect(d.category == sut.category)
        #expect(d.displayState == sut.displayState)

        #expect(d.dice_.update != sut.dice_.update)
        #expect(d.entries.count == sut.entries.count)
        #expect(d.sumUp == sut.sumUp)
        #expect(d.modifier == sut.modifier)
        #expect(d.percentDice == sut.percentDice)
        #expect(d.compareOption == sut.compareOption)
        #expect(d.compareValue == sut.compareValue)
        #expect(d.coupValues == sut.coupValues)
        #expect(d.coupOnlyOnFirstDie == sut.coupOnlyOnFirstDie)
        #expect(d.fumbleValues == sut.fumbleValues)
        #expect(d.fumbleOnlyOnFirstDie == sut.fumbleOnlyOnFirstDie)
        #expect(d.rerollOptions == sut.rerollOptions)
        #expect(d.reorderDice == sut.reorderDice)
        #expect(d.addDiceEvery == sut.addDiceEvery)
        #expect(nil == d.resultCategory)

        #expect(d.name == "\(a.name) Copy")
        #expect(d.name_.rawValue != sut.name_.rawValue)
        #expect(d.dice_.update != sut.dice_.update)

        let merged = sut.merge(a)
        #expect(merged.isSame(sut))
        #expect(merged == a)
    }

    @Test func changeValues() async throws {
        let sut = try await setUp()
        let a = sut.copy()
        a.name = "Next Name"
        #expect(a.name == "Next Name")
        #expect(sut.name == "TestName")

        let b = sut
        let merged = b.merge(a)
        #expect(merged.name == "Next Name")
    }
}
#endif
