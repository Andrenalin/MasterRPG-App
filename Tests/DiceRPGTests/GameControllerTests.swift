// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import DiceRPG

@MainActor
struct GameControllerTests {
    @Test func setGameDice() async throws {
        let (root, dice) = await GameControllerTests.setupDice()
        let sut = root.gameController
        
        #expect(sut.gameModel.items.count == 1)
        #expect(sut.gameModel.items.first == dice.id)
    }

    @Test func gameSessionStateAndPlayerDice() async throws {
        let (root, dice) = await GameControllerTests.setupDice()
        let sut = root.gameController

        let renamed = dice.copy()
        renamed.name = "Renamed"
        sut.setGame(item: renamed, itemId: dice.id)
        #expect(sut.gameItem(for: dice.id).name == "Renamed")

        let gameDiceId = sut.createGameDice(for: dice.id, gameDiceId: nil)
        #expect(sut.gameItem(for: gameDiceId).category == .value)
        let reusedGameDiceId = sut.createGameDice(for: dice.id, gameDiceId: gameDiceId)
        #expect(reusedGameDiceId == gameDiceId)

        await sut.setFocusDice(on: dice.id)
        #expect(sut.isFocusedDice(itemId: dice.id))
        await sut.setFocusDice(on: nil)
        #expect(!sut.gameModel.focusItemIds.isEmpty)

        #expect(sut.canEditDice(itemId: dice.id, isGameMode: false))
        #expect(!sut.canEditDice(itemId: dice.id, isGameMode: true))

        let activeDice = sut.gameItem(for: dice.id)
        activeDice.dice = GameControllerTests.diceResult(values: [[3], [4], [5]])
        #expect(sut.hasResults(itemId: dice.id))
        sut.gameModel.focusItemIds = []
        #expect(sut.isPlayerDice(itemId: dice.id))

        await sut.toggleHidden(playerId: dice.id)
        #expect(sut.isPlayerHidden(playerId: dice.id))
        await sut.toggleHidden(playerId: dice.id)
        #expect(!sut.isPlayerHidden(playerId: dice.id))

        #expect(sut.number(for: dice.id, result: "3|4|5") == 12)
        sut.validateForValue(diceId: gameDiceId, compareValue: 12)
        #expect(sut.gameItem(for: gameDiceId).compareValue == 12)
        sut.validateForValue(diceId: gameDiceId, compareValue: nil)
        #expect(sut.gameItem(for: gameDiceId).compareValue == 12)

        let playerDiceA = DiceModel(id: UUID(), name: "A", dice: [])
        let playerDiceB = DiceModel(id: UUID(), name: "B", dice: [])
        sut.diceGameModel.playerDice = [playerDiceA, playerDiceB]
        sut.resetPlayerDice(to: ["B"])
        #expect(sut.diceGameModel.playerDice.map(\.name) == ["B"])

        await sut.resetCompareValue(of: dice.id, value: 9)
        let focusedId = try #require(sut.gameModel.focusItemIds.first)
        #expect(sut.gameItem(for: focusedId).compareValue == 9)

        let removableDie = activeDice.dice[0]
        let count = activeDice.dice.count
        sut.remove(die: removableDie, from: dice.id)
        #expect(activeDice.dice.count == count - 1)

    }

    @Test func gameNetworkResultPayloads() async throws {
        let (root, dice) = await GameControllerTests.setupDice()
        let sut = root.gameController
        let resultCategory = ResultCategory(id: UUID(), module: .table)
        dice.dice = GameControllerTests.diceResult(values: [[2], [3], [4]])

        let resultData = await sut.createDiceResult(for: dice.id, resultCategory: resultCategory)
        #expect(resultData.type == .dice)
        let decoded = try #require(DiceResultModel.decodeData(of: resultData.data))
        #expect(decoded.diceModel.resultCategory == resultCategory)

        let playerResult = sut.addGameDiceResult(
            data: resultData,
            name: "Player One",
            supporterTier: .gold,
            isGameMaster: true
        )
        #expect(playerResult.0 == decoded.values)
        #expect(playerResult.1 == resultCategory)
        #expect(sut.diceGameModel.masterDiceName == "Player One")
        #expect(sut.diceGameModel.playerDice.count == 1)
        let playerDiceID = try #require(sut.diceGameModel.playerDice.first?.id)
        #expect(sut.supporterTier(playerId: playerDiceID) == .gold)

        _ = sut.addGameDiceResult(
            data: resultData,
            name: "Player One",
            supporterTier: .silver,
            isGameMaster: false
        )
        #expect(sut.diceGameModel.playerDice.count == 1)

        let invalidResult = sut.addGameDiceResult(
            data: NetworkCodableDataType(id: UUID(), type: .dice, version: 0),
            name: "Nobody",
            supporterTier: .none,
            isGameMaster: false
        )
        #expect(invalidResult.0 == nil)
        #expect(invalidResult.1 == nil)

        let oldResultCategory = dice.resultCategory
        let gameData = try await sut.createGameData(for: dice.id, resultCategory: resultCategory)
        #expect(dice.resultCategory == oldResultCategory)
        try await sut.updateGame(data: gameData, hide: false, focus: true)
        #expect(sut.gameModel.focusItemIds.first == dice.id)
    }
    
    @Test func fumble() async throws {
        let (root, dice) = await GameControllerTests.setupDice()
        let sut = root.gameController
        
        var fumble = sut.fumble(for: dice.id)
        #expect(!fumble)
        dice.dice = GameControllerTests.diceResult(values: [[20], [1, 12], [15]])
        fumble = sut.fumble(for: dice.id)
        #expect(fumble)
        dice.dice = GameControllerTests.diceResult(values: [[12], [1, 12], [20]])
        fumble = sut.fumble(for: dice.id)
        #expect(!fumble)
        dice.dice = GameControllerTests.diceResult(values: [[12], [20], [20]])
        fumble = sut.fumble(for: dice.id)
        #expect(!fumble)
        dice.dice = GameControllerTests.diceResult(values: [[1, 20], [20], [20]])
        fumble = sut.fumble(for: dice.id)
        #expect(!fumble)
        dice.fumbleOnlyOnFirstDie = false
        fumble = sut.fumble(for: dice.id)
        #expect(fumble)
        dice.fumbleOnlyOnFirstDie = true
        dice.dice = GameControllerTests.diceResult(values: [[10], [10], [10]])
        dice.fumbleValues = [.result(10)]
        fumble = sut.fumble(for: dice.id)
        #expect(fumble)
        dice.fumbleOnlyOnFirstDie = false
        dice.dice = GameControllerTests.diceResult(values: [[10], [10], [10]])
        dice.fumbleValues = [.result(30)]
        fumble = sut.fumble(for: dice.id)
        #expect(fumble)
        dice.dice = GameControllerTests.diceResult(values: [[1, 12], [1, 1, 15], [1, 20]])
        dice.fumbleValues = [.result(3)]
        fumble = sut.fumble(for: dice.id)
        #expect(fumble)
        dice.fumbleOnlyOnFirstDie = true
        dice.dice = GameControllerTests.diceResult(values: [[18], [20], [19]])
        dice.fumbleValues = [.diceValue(19), .diceValue(20)]
        fumble = sut.fumble(for: dice.id)
        #expect(!fumble)
        dice.fumbleValues = [.diceValue(18), .diceValue(20)]
        fumble = sut.fumble(for: dice.id)
        #expect(fumble)
    }
    
    @Test func coup() async throws {
        let (root, dice) = await GameControllerTests.setupDice()
        let sut = root.gameController
        
        var coup = sut.coup(for: dice.id)
        #expect(!coup)
        dice.dice = GameControllerTests.diceResult(values: [[20], [1, 12], [15]])
        coup = sut.coup(for: dice.id)
        #expect(coup)
        dice.coupOnlyOnFirstDie = true
        dice.dice = GameControllerTests.diceResult(values: [[12], [1, 12], [20]])
        coup = sut.coup(for: dice.id)
        #expect(!coup)
        dice.dice = GameControllerTests.diceResult(values: [[1, 20], [4], [5]])
        coup = sut.coup(for: dice.id)
        #expect(coup)
        dice.dice = GameControllerTests.diceResult(values: [[1, 20], [1, 12], [1, 1, 3]])
        dice.coupValues = [.result(3)]
        coup = sut.coup(for: dice.id)
        #expect(!coup)
        dice.coupOnlyOnFirstDie = false
        coup = sut.coup(for: dice.id)
        #expect(coup)
        dice.coupValues = [.diceValue(1), .diceValue(2), .diceValue(3)]
        dice.dice = GameControllerTests.diceResult(values: [[10], [3], [4]])
        coup = sut.coup(for: dice.id)
        #expect(coup)
        dice.dice = GameControllerTests.diceResult(values: [[10], [5], [4]])
        coup = sut.coup(for: dice.id)
        #expect(!coup)
    }
    
    @Test func maxValuePerDice() async throws {
        let (root, dice) = await GameControllerTests.setupDice()
        let sut = root.gameController
        dice.dice = GameControllerTests.diceResult(values: [[1, 20], [1, 12], [1, 1, 3]])
        
        var max = sut.maxValuePerDice(for: 1, itemId: dice.id)
        #expect(max == 20)
        max = sut.maxValuePerDice(for: 2, itemId: dice.id)
        #expect(max == 20)
        max = sut.maxValuePerDice(for: 3, itemId: dice.id)
        #expect(max == 4)
        max = sut.maxValuePerDice(for: 4, itemId: dice.id)
        #expect(max == 0)
        dice.addDiceEvery = 0
        max = sut.maxValuePerDice(for: 3, itemId: dice.id)
        #expect(max == 20)
    }
    
    @Test func reorder() async throws {
        let (root, dice) = await GameControllerTests.setupDice()
        let sut = root.gameController

        var reorder = sut.reorder(for: dice.id)
        #expect(reorder.map { $0.id } == [GameControllerTests.dieUUID1, GameControllerTests.dieUUID2, GameControllerTests.dieUUID3])
        dice.dice = GameControllerTests.diceResult(values: [[3], [1], [2]])
        reorder = sut.reorder(for: dice.id)
        #expect(reorder.map { $0.id } == [GameControllerTests.dieUUID2, GameControllerTests.dieUUID1, GameControllerTests.dieUUID3])
        dice.dice = GameControllerTests.diceResult(values: [[3, 20], [2], [19]])
        reorder = sut.reorder(for: dice.id)
        #expect(reorder.map { $0.id } == [GameControllerTests.dieUUID3, GameControllerTests.dieUUID1, GameControllerTests.dieUUID2])
        dice.rerollOptions = [DiceModel.RerollOption(number: 3, value: 18, maxDiceValue: false)]
        dice.dice = GameControllerTests.diceResult(values: [[3, 20], [17], [19]])
        reorder = sut.reorder(for: dice.id)
        #expect(reorder.map { $0.id } == [GameControllerTests.dieUUID3, GameControllerTests.dieUUID1, GameControllerTests.dieUUID2])
        dice.coupValues = [.diceValue(1), .diceValue(2), .diceValue(3)]
        dice.dice = GameControllerTests.diceResult(values: [[1, 2, 3, 4], [2, 3, 5], [20]])
        dice.rerollOptions = [
            DiceModel.RerollOption(number: 1, value: 0, maxDiceValue: true),
            DiceModel.RerollOption(number: 2, value: 19, maxDiceValue: false),
            DiceModel.RerollOption(number: 3, value: 18, maxDiceValue: false),
        ]
        reorder = sut.reorder(for: dice.id)
        #expect(reorder.map { $0.id } == [GameControllerTests.dieUUID1, GameControllerTests.dieUUID3, GameControllerTests.dieUUID2])
        dice.rerollOptions = [
            DiceModel.RerollOption(number: 1, value: 0, maxDiceValue: true),
            DiceModel.RerollOption(number: 2, value: 0, maxDiceValue: true),
            DiceModel.RerollOption(number: 3, value: 0, maxDiceValue: true),
        ]
        reorder = sut.reorder(for: dice.id)
        #expect(reorder.map { $0.id } == [GameControllerTests.dieUUID1, GameControllerTests.dieUUID2, GameControllerTests.dieUUID3])
    }
    
    @Test func calculate() async throws {
        let (root, dice) = await GameControllerTests.setupDice()
        let sut = root.gameController

        var result = sut.calculate(itemId: dice.id)
        #expect(!result.checked)
        #expect(result.result == .notRolled)
        dice.dice = GameControllerTests.diceResult(values: [[3], [4], [2]])
        result = sut.calculate(itemId: dice.id)
        #expect(result.checked)
        #expect(result.sum == 9)
        dice.dice = GameControllerTests.diceResult(values: [[19], [20], [2]])
        result = sut.calculate(itemId: dice.id)
        #expect(result.checked)
        #expect(result.sum == 41)
        dice.dice = GameControllerTests.diceResult(values: [[20], [19], [2]])
        result = sut.calculate(itemId: dice.id)
        #expect(!result.checked)
        #expect(result.result == .fumble)
        dice.dice = GameControllerTests.diceResult(values: [[5], [1, 12], [20]])
        result = sut.calculate(itemId: dice.id)
        #expect(result.checked)
        #expect(result.result == .coup)
        #expect(result.sum == 52)
        dice.dice = GameControllerTests.diceResult(values: [[4], [1, 12], [20]])
        result = sut.calculate(itemId: dice.id)
        #expect(result.checked)
        #expect(result.result == .coup)
        #expect(result.sum == 56)
        dice.coupValues = [.diceValue(1), .diceValue(2), .diceValue(3)]
        dice.dice = GameControllerTests.diceResult(values: [[1, 2, 3, 4], [2, 3, 5], [20]])
        result = sut.calculate(itemId: dice.id)
        #expect(result.checked)
        #expect(result.result == .coup)
        #expect(result.sum == 54)
        dice.rerollOptions = [
            DiceModel.RerollOption(number: 1, value: 0, maxDiceValue: true),
            DiceModel.RerollOption(number: 2, value: 0, maxDiceValue: true),
            DiceModel.RerollOption(number: 3, value: 0, maxDiceValue: true),
        ]
        result = sut.calculate(itemId: dice.id)
        #expect(result.checked)
        #expect(result.result == .coup)
        #expect(result.sum == 109)
        dice.rerollOptions = [
            DiceModel.RerollOption(number: 1, value: 0, maxDiceValue: true),
            DiceModel.RerollOption(number: 2, value: 19, maxDiceValue: false),
            DiceModel.RerollOption(number: 3, value: 18, maxDiceValue: false),
        ]
        dice.dice = GameControllerTests.diceResult(values: [[1, 2, 3, 4], [2, 3, 5], [10]])
        result = sut.calculate(itemId: dice.id)
        #expect(result.checked)
        #expect(result.result == .coup)
        #expect(result.sum == 103)
    }
    
    @Test func result() async throws {
        let (root, dice) = await GameControllerTests.setupDice()
        let sut = root.gameController

        dice.dice = GameControllerTests.diceResult(values: [[1, 20], [1, 12], [1, 1, 4]])
        var result = sut.resultText(itemId: dice.id)
        #expect(result == "1,20|1,12|1,1,4<=44 ∑84 Coup✅")
        dice.dice = GameControllerTests.diceResult(values: [[20], [1, 12], [1, 1, 4]])
        result = sut.resultText(itemId: dice.id)
        #expect(result == "20|1,12|1,1,4<=44 Fumble❌")
        dice.rerollOptions = [
            DiceModel.RerollOption(number: 1, value: 0, maxDiceValue: true),
            DiceModel.RerollOption(number: 2, value: 0, maxDiceValue: true),
            DiceModel.RerollOption(number: 3, value: 0, maxDiceValue: true),
        ]
        dice.dice = GameControllerTests.diceResult(values: [[3, 2, 1, 19], [20], [1, 1, 4]])
        result = sut.resultText(itemId: dice.id)
        #expect(result == "3,2,1,19|20|1,1,4<=44 ∑123 Coup✅")
    }
    
    @Test func reset() async throws {
        let (root, dice) = await GameControllerTests.setupDice()
        let sut = root.gameController

        dice.dice = GameControllerTests.diceResult(values: [[1, 20], [1, 12], [1, 1, 4]])
        sut.reset(for: dice.id)
        #expect(dice.dice.map { $0.result } == [[], [], []])
    }
    
    @Test func role() async throws {
        let (root, dice) = await GameControllerTests.setupDice()
        let sut = root.gameController

        dice.dice = GameControllerTests.diceResult(values: [[], [], []])
        sut.role(die: dice.dice[0], for: dice.id)
        #expect(dice.dice.map { $0.result.count > 0 } == [true, false, false])
        sut.role(die: dice.dice[1], for: dice.id)
        #expect(dice.dice.map { $0.result.count > 0 } == [true, true, false])
        sut.role(die: dice.dice[2], for: dice.id)
        #expect(dice.dice.map { $0.result.count > 0 } == [true, true, true])
        dice.dice = GameControllerTests.diceResult(values: [[], [], []])
        sut.role(die: nil, for: dice.id)
        #expect(dice.dice.map { $0.result.count > 0 } == [true, true, true])
    }
    
    @Test func diceSuccess() async throws {
        let (root, dice) = await GameControllerTests.setupDice()
        let sut = root.gameController

        dice.dice = GameControllerTests.diceResult(values: [[1, 20], [1, 12], [1, 1, 4]])
        var result = sut.diceSuccess(for: dice.id)
        #expect(GameControllerTests.compare(lhs: result, rhs: [(GameControllerTests.dieUUID1, [true, true]), (GameControllerTests.dieUUID2, [true, true]), (GameControllerTests.dieUUID3, [true, true, true])]))
        dice.dice = GameControllerTests.diceResult(values: [[1, 20], [1, 12], [1, 1, 5]])
        result = sut.diceSuccess(for: dice.id)
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
    static func setupDice() async -> (DiceRootModel, DiceModel) {
        let root = DiceRootModel.testRoot()
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
        root.itemController.replace(model: dice, isInsert: true)
        let gameDice = root.gameController.gameItem(for: dice.id)
        #expect(gameDice == dice)
        root.gameController.setGame(item: gameDice, itemId: dice.id)
        return (root, dice)
    }
}
#endif
