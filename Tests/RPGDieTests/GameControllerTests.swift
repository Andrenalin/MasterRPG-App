// @copyright André Trettin

#if canImport(Testing)
import AndrenalinKit
import Foundation
import Testing

@testable import RPGDie

struct GameControllerTests {
    @Test func setGameDice() async throws {
        let (root, dice) = await GameControllerTests.setupDice()
        let sut = root.gameController
        
        #expect(await sut.gameModel.items.count == 1)
        #expect(await sut.gameModel.items.first == dice.id)
    }
    
    @Test func fumble() async throws {
        let (root, dice) = await GameControllerTests.setupDice()
        let sut = root.gameController
        
        var fumble = await sut.fumble(for: dice.id)
        #expect(!fumble)
        dice.entries = GameControllerTests.diceResult(values: [[20], [1, 12], [15]])
        fumble = await sut.fumble(for: dice.id)
        #expect(fumble)
        dice.entries = GameControllerTests.diceResult(values: [[12], [1, 12], [20]])
        fumble = await sut.fumble(for: dice.id)
        #expect(!fumble)
        dice.entries = GameControllerTests.diceResult(values: [[12], [20], [20]])
        fumble = await sut.fumble(for: dice.id)
        #expect(!fumble)
        dice.entries = GameControllerTests.diceResult(values: [[1, 20], [20], [20]])
        fumble = await sut.fumble(for: dice.id)
        #expect(!fumble)
        dice.fumbleOnlyOnFirstDie = false
        fumble = await sut.fumble(for: dice.id)
        #expect(fumble)
        dice.fumbleOnlyOnFirstDie = true
        dice.entries = GameControllerTests.diceResult(values: [[10], [10], [10]])
        dice.fumbleValues = [.result(10)]
        fumble = await sut.fumble(for: dice.id)
        #expect(fumble)
        dice.fumbleOnlyOnFirstDie = false
        dice.entries = GameControllerTests.diceResult(values: [[10], [10], [10]])
        dice.fumbleValues = [.result(30)]
        fumble = await sut.fumble(for: dice.id)
        #expect(fumble)
        dice.entries = GameControllerTests.diceResult(values: [[1, 12], [1, 1, 15], [1, 20]])
        dice.fumbleValues = [.result(3)]
        fumble = await sut.fumble(for: dice.id)
        #expect(fumble)
        dice.fumbleOnlyOnFirstDie = true
        dice.entries = GameControllerTests.diceResult(values: [[18], [20], [19]])
        dice.fumbleValues = [.diceValue(19), .diceValue(20)]
        fumble = await sut.fumble(for: dice.id)
        #expect(!fumble)
        dice.fumbleValues = [.diceValue(18), .diceValue(20)]
        fumble = await sut.fumble(for: dice.id)
        #expect(fumble)
    }
    
    @Test func coup() async throws {
        let (root, dice) = await GameControllerTests.setupDice()
        let sut = root.gameController
        
        var coup = await sut.coup(for: dice.id)
        #expect(!coup)
        dice.entries = GameControllerTests.diceResult(values: [[20], [1, 12], [15]])
        coup = await sut.coup(for: dice.id)
        #expect(coup)
        dice.coupOnlyOnFirstDie = true
        dice.entries = GameControllerTests.diceResult(values: [[12], [1, 12], [20]])
        coup = await sut.coup(for: dice.id)
        #expect(!coup)
        dice.entries = GameControllerTests.diceResult(values: [[1, 20], [4], [5]])
        coup = await sut.coup(for: dice.id)
        #expect(coup)
        dice.entries = GameControllerTests.diceResult(values: [[1, 20], [1, 12], [1, 1, 3]])
        dice.coupValues = [.result(3)]
        coup = await sut.coup(for: dice.id)
        #expect(!coup)
        dice.coupOnlyOnFirstDie = false
        coup = await sut.coup(for: dice.id)
        #expect(coup)
        dice.coupValues = [.diceValue(1), .diceValue(2), .diceValue(3)]
        dice.entries = GameControllerTests.diceResult(values: [[10], [3], [4]])
        coup = await sut.coup(for: dice.id)
        #expect(coup)
        dice.entries = GameControllerTests.diceResult(values: [[10], [5], [4]])
        coup = await sut.coup(for: dice.id)
        #expect(!coup)
    }
    
    @Test func maxValuePerDice() async throws {
        let (root, dice) = await GameControllerTests.setupDice()
        let sut = root.gameController
        dice.entries = GameControllerTests.diceResult(values: [[1, 20], [1, 12], [1, 1, 3]])
        
        var max = await sut.maxValuePerDice(for: 1, itemId: dice.id)
        #expect(max == 20)
        max = await sut.maxValuePerDice(for: 2, itemId: dice.id)
        #expect(max == 20)
        max = await sut.maxValuePerDice(for: 3, itemId: dice.id)
        #expect(max == 4)
        max = await sut.maxValuePerDice(for: 4, itemId: dice.id)
        #expect(max == 0)
        dice.addDiceEvery = 0
        max = await sut.maxValuePerDice(for: 3, itemId: dice.id)
        #expect(max == 20)
    }
    
    @Test func reorder() async throws {
        let (root, dice) = await GameControllerTests.setupDice()
        let sut = root.gameController

        var reorder = await sut.reorder(for: dice.id)
        #expect(reorder.map { $0.id } == [GameControllerTests.dieUUID1, GameControllerTests.dieUUID2, GameControllerTests.dieUUID3])
        dice.entries = GameControllerTests.diceResult(values: [[3], [1], [2]])
        reorder = await sut.reorder(for: dice.id)
        #expect(reorder.map { $0.id } == [GameControllerTests.dieUUID2, GameControllerTests.dieUUID1, GameControllerTests.dieUUID3])
        dice.entries = GameControllerTests.diceResult(values: [[3, 20], [2], [19]])
        reorder = await sut.reorder(for: dice.id)
        #expect(reorder.map { $0.id } == [GameControllerTests.dieUUID3, GameControllerTests.dieUUID1, GameControllerTests.dieUUID2])
        dice.rerollOptions = [DiceModel.RerollOption(number: 3, value: 18, maxDiceValue: false)]
        dice.entries = GameControllerTests.diceResult(values: [[3, 20], [17], [19]])
        reorder = await sut.reorder(for: dice.id)
        #expect(reorder.map { $0.id } == [GameControllerTests.dieUUID3, GameControllerTests.dieUUID1, GameControllerTests.dieUUID2])
        dice.coupValues = [.diceValue(1), .diceValue(2), .diceValue(3)]
        dice.entries = GameControllerTests.diceResult(values: [[1, 2, 3, 4], [2, 3, 5], [20]])
        dice.rerollOptions = [
            DiceModel.RerollOption(number: 1, value: 0, maxDiceValue: true),
            DiceModel.RerollOption(number: 2, value: 19, maxDiceValue: false),
            DiceModel.RerollOption(number: 3, value: 18, maxDiceValue: false),
        ]
        reorder = await sut.reorder(for: dice.id)
        #expect(reorder.map { $0.id } == [GameControllerTests.dieUUID1, GameControllerTests.dieUUID3, GameControllerTests.dieUUID2])
        dice.rerollOptions = [
            DiceModel.RerollOption(number: 1, value: 0, maxDiceValue: true),
            DiceModel.RerollOption(number: 2, value: 0, maxDiceValue: true),
            DiceModel.RerollOption(number: 3, value: 0, maxDiceValue: true),
        ]
        reorder = await sut.reorder(for: dice.id)
        #expect(reorder.map { $0.id } == [GameControllerTests.dieUUID1, GameControllerTests.dieUUID2, GameControllerTests.dieUUID3])
    }
    
    @Test func calculate() async throws {
        let (root, dice) = await GameControllerTests.setupDice()
        let sut = root.gameController

        var result = await sut.calculate(itemId: dice.id)
        #expect(!result.checked)
        #expect(result.result == .notRolled)
        dice.entries = GameControllerTests.diceResult(values: [[3], [4], [2]])
        result = await sut.calculate(itemId: dice.id)
        #expect(result.checked)
        #expect(result.sum == 9)
        dice.entries = GameControllerTests.diceResult(values: [[19], [20], [2]])
        result = await sut.calculate(itemId: dice.id)
        #expect(result.checked)
        #expect(result.sum == 41)
        dice.entries = GameControllerTests.diceResult(values: [[20], [19], [2]])
        result = await sut.calculate(itemId: dice.id)
        #expect(!result.checked)
        #expect(result.result == .fumble)
        dice.entries = GameControllerTests.diceResult(values: [[5], [1, 12], [20]])
        result = await sut.calculate(itemId: dice.id)
        #expect(result.checked)
        #expect(result.result == .coup)
        #expect(result.sum == 52)
        dice.entries = GameControllerTests.diceResult(values: [[4], [1, 12], [20]])
        result = await sut.calculate(itemId: dice.id)
        #expect(result.checked)
        #expect(result.result == .coup)
        #expect(result.sum == 56)
        dice.coupValues = [.diceValue(1), .diceValue(2), .diceValue(3)]
        dice.entries = GameControllerTests.diceResult(values: [[1, 2, 3, 4], [2, 3, 5], [20]])
        result = await sut.calculate(itemId: dice.id)
        #expect(result.checked)
        #expect(result.result == .coup)
        #expect(result.sum == 54)
        dice.rerollOptions = [
            DiceModel.RerollOption(number: 1, value: 0, maxDiceValue: true),
            DiceModel.RerollOption(number: 2, value: 0, maxDiceValue: true),
            DiceModel.RerollOption(number: 3, value: 0, maxDiceValue: true),
        ]
        result = await sut.calculate(itemId: dice.id)
        #expect(result.checked)
        #expect(result.result == .coup)
        #expect(result.sum == 109)
        dice.rerollOptions = [
            DiceModel.RerollOption(number: 1, value: 0, maxDiceValue: true),
            DiceModel.RerollOption(number: 2, value: 19, maxDiceValue: false),
            DiceModel.RerollOption(number: 3, value: 18, maxDiceValue: false),
        ]
        dice.entries = GameControllerTests.diceResult(values: [[1, 2, 3, 4], [2, 3, 5], [10]])
        result = await sut.calculate(itemId: dice.id)
        #expect(result.checked)
        #expect(result.result == .coup)
        #expect(result.sum == 103)
    }
    
    @Test func result() async throws {
        let (root, dice) = await GameControllerTests.setupDice()
        let sut = root.gameController

        dice.entries = GameControllerTests.diceResult(values: [[1, 20], [1, 12], [1, 1, 4]])
        var result = await sut.resultText(itemId: dice.id)
        #expect(result == "1,20|1,12|1,1,4<=44 ∑84 Coup✅")
        dice.entries = GameControllerTests.diceResult(values: [[20], [1, 12], [1, 1, 4]])
        result = await sut.resultText(itemId: dice.id)
        #expect(result == "20|1,12|1,1,4<=44 Fumble❌")
        dice.rerollOptions = [
            DiceModel.RerollOption(number: 1, value: 0, maxDiceValue: true),
            DiceModel.RerollOption(number: 2, value: 0, maxDiceValue: true),
            DiceModel.RerollOption(number: 3, value: 0, maxDiceValue: true),
        ]
        dice.entries = GameControllerTests.diceResult(values: [[3, 2, 1, 19], [20], [1, 1, 4]])
        result = await sut.resultText(itemId: dice.id)
        #expect(result == "3,2,1,19|20|1,1,4<=44 ∑123 Coup✅")
    }
    
    @Test func reset() async throws {
        let (root, dice) = await GameControllerTests.setupDice()
        let sut = root.gameController

        dice.entries = GameControllerTests.diceResult(values: [[1, 20], [1, 12], [1, 1, 4]])
        await sut.reset(for: dice.id)
        #expect(dice.entries.map { $0.result } == [[], [], []])
    }
    
    @Test func role() async throws {
        let (root, dice) = await GameControllerTests.setupDice()
        let sut = root.gameController

        dice.entries = GameControllerTests.diceResult(values: [[], [], []])
        await sut.role(die: dice.entries[0], for: dice.id)
        #expect(dice.entries.map { $0.result.count > 0 } == [true, false, false])
        await sut.role(die: dice.entries[1], for: dice.id)
        #expect(dice.entries.map { $0.result.count > 0 } == [true, true, false])
        await sut.role(die: dice.entries[2], for: dice.id)
        #expect(dice.entries.map { $0.result.count > 0 } == [true, true, true])
        dice.entries = GameControllerTests.diceResult(values: [[], [], []])
        await sut.role(die: nil, for: dice.id)
        #expect(dice.entries.map { $0.result.count > 0 } == [true, true, true])
    }
    
    @Test func diceSuccess() async throws {
        let (root, dice) = await GameControllerTests.setupDice()
        let sut = root.gameController

        dice.entries = GameControllerTests.diceResult(values: [[1, 20], [1, 12], [1, 1, 4]])
        var result = await sut.diceSuccess(for: dice.id)
        #expect(GameControllerTests.compare(lhs: result, rhs: [(GameControllerTests.dieUUID1, [true, true]), (GameControllerTests.dieUUID2, [true, true]), (GameControllerTests.dieUUID3, [true, true, true])]))
        dice.entries = GameControllerTests.diceResult(values: [[1, 20], [1, 12], [1, 1, 5]])
        result = await sut.diceSuccess(for: dice.id)
        #expect(GameControllerTests.compare(lhs: result, rhs: [(GameControllerTests.dieUUID1, [true, true]), (GameControllerTests.dieUUID2, [true, true]), (GameControllerTests.dieUUID3, [true, true, false])]))
    }
}

private extension GameControllerTests {
    static let dieUUID1 = UUID()
    static let dieUUID2 = UUID()
    static let dieUUID3 = UUID()
    
    static func compare(lhs: [(UUID, [Bool])], rhs: [(UUID, [Bool])]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).map {
            $0.0 == $1.0 && $0.1 == $1.1
        }.reduce(true) { $0 && $1 }
    }

    static func diceResult(values: [[Int]]) -> [DieModel] {
        return [
            DieModel(id: dieUUID1, die: .twenty, rotation: 0, result: values[0], displayState: 3),
            DieModel(id: dieUUID2, die: .twenty, rotation: 0, result: values[1], displayState: 3),
            DieModel(id: dieUUID3, die: .twenty, rotation: 0, result: values[2], displayState: 3),
        ]
    }

    @MainActor
    static func setupDice() async -> (DiceRoot, DiceModel) {
        let root = DiceRoot.testRoot()
        await root.itemController.resetData()
        await root.gameController.reset()

        let dice = DiceModel(
            id: UUID(),
            name: "TestName",
            description: "Hello something",
            tags: ["DS", "Good"],
            category: .table,
            displayState: 3,
            dice: GameControllerTests.diceResult(values: [[], [], []]),
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
        root.itemController.replace(model: dice, isInsert: true, shouldRepairLinks: true)
        let gameDice = root.gameController.gameItem(for: dice.id)
        #expect(gameDice == dice)
        root.gameController.setGame(item: gameDice, itemId: dice.id)
        return (root, dice)
    }
}
#endif
