// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import DiceRPG

@MainActor
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
            rerollOptions: [DiceModel.RerollOption(number: 1, value: 0, maxDiceValue: true)],
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

    // MARK: - Colour inheritance

    @Test func dieDuplicateKeepsColorAndGetsNewId() {
        let die = DieModel(id: UUID(), die: .twenty, color: DieModel.ColorCode.A.rawValue)
        let copy = die.duplicate()
        #expect(copy.color == "A")
        #expect(copy.id != die.id)
    }

    @Test func changingCompareValueKeepsDiceColor() {
        let model = DiceModel(id: UUID(), dice: [DieModel(id: UUID(), die: .twenty, color: DieModel.ColorCode.A.rawValue)], addDiceEvery: 20)
        model.compareValue = 45
        #expect(model.dice.count == 3)
        #expect(model.dice.allSatisfy { $0.color == "A" })
        model.compareValue = 10
        #expect(model.dice.count == 1)
        #expect(model.dice.allSatisfy { $0.color == "A" })
    }

    @Test func activatingAddDiceKeepsDiceColor() {
        let model = DiceModel(id: UUID(), dice: [DieModel(id: UUID(), die: .twenty, color: DieModel.ColorCode.A.rawValue)], compareValue: 60)
        model.addDiceActivate = true
        #expect(model.dice.count == 3)
        #expect(model.dice.allSatisfy { $0.color == "A" })
    }

    @Test func diceModelDuplicateKeepsEachDieColor() {
        let model = DiceModel(id: UUID(), dice: [
            DieModel(id: UUID(), die: .twenty, color: DieModel.ColorCode.A.rawValue),
            DieModel(id: UUID(), die: .twenty, color: DieModel.ColorCode.G.rawValue),
        ])
        let copy = model.duplicate()
        #expect(copy.dice.map(\.color) == ["A", "G"])
    }
}
#endif
