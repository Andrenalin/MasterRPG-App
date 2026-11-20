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

    @Test func tossedDieIsRolledByItsSheetAlone() async throws {
        let (root, dice) = await GameControllerTests.setupDice()
        let sut = root.gameController
        let activeDice = sut.gameItem(for: dice.id)
        activeDice.dice = GameControllerTests.diceResult(values: [[3], [4], [5]])
        let tossed = try #require(activeDice.dice.first)

        let face = try #require(sut.rollDie(tossed.id, of: dice.id, networkActions: nil))

        let rolled = sut.gameItem(for: dice.id).dice
        #expect(rolled[0].result.last == face)
        #expect((1...rolled[0].die.max).contains(face))
        // The other dice keep their results.
        #expect(rolled[1].result == [4])
        #expect(rolled[2].result == [5])
        #expect(sut.rollDie(UUID(), of: dice.id, networkActions: nil) == nil)
        #expect(sut.rollDie(tossed.id, of: UUID(), networkActions: nil) == nil)
    }

    @Test func overlayResultLookupsForTheTable() async throws {
        let (root, dice) = await GameControllerTests.setupDice()
        let sut = root.gameController

        let item = sut.gameItem(for: dice.id)
        item.sumUp = false
        item.compareOption = .off
        #expect(!sut.showsResult(for: dice.id))
        item.sumUp = true
        #expect(sut.showsResult(for: dice.id))
        #expect(!sut.showsResult(for: UUID()))

        let playerDice = DiceModel(id: UUID(), name: "Anna Example", dice: [])
        sut.setGame(item: playerDice, itemId: playerDice.id)
        sut.diceGameModel.playerDice = [playerDice]
        #expect(sut.playerDiceId(named: "Anna Example") == playerDice.id)
        #expect(sut.playerDiceId(named: "Nobody") == nil)
        sut.toggleHidden(playerId: playerDice.id)
        #expect(sut.playerDiceId(named: "Anna Example") == nil)
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

        sut.toggleHidden(playerId: dice.id)
        #expect(sut.isPlayerHidden(playerId: dice.id))
        sut.toggleHidden(playerId: dice.id)
        #expect(!sut.isPlayerHidden(playerId: dice.id))

        sut.validateForValue(diceId: gameDiceId, compareValue: 12)
        #expect(sut.gameItem(for: gameDiceId).compareValue == 12)
        sut.validateForValue(diceId: gameDiceId, compareValue: nil)
        #expect(sut.gameItem(for: gameDiceId).compareValue == 12)

        let playerDiceA = DiceModel(id: UUID(), name: "A", dice: [])
        let playerDiceB = DiceModel(id: UUID(), name: "B", dice: [])
        sut.diceGameModel.playerDice = [playerDiceA, playerDiceB]
        sut.resetPlayerDice(keepingSenders: [], names: ["B"])
        #expect(sut.diceGameModel.playerDice.map(\.name) == ["B"])

        await sut.resetCompareValue(of: dice.id, value: 9)
        let focusedId = try #require(sut.gameModel.focusItemIds.first)
        #expect(sut.gameItem(for: focusedId).compareValue == 9)

        let removableDie = activeDice.dice[0]
        let count = activeDice.dice.count
        sut.remove(die: removableDie, from: dice.id)
        #expect(activeDice.dice.count == count - 1)

    }

    @Test("Two players with the same display name keep their own dice when they are told apart by sender id")
    func namesakesKeepTheirOwnDice() async throws {
        let (root, dice) = await GameControllerTests.setupDice()
        let sut = root.gameController
        dice.dice = GameControllerTests.diceResult(values: [[2], [3], [4]])
        let data = await sut.createDiceResult(for: dice.id, resultCategory: nil)
        let first = UUID()
        let second = UUID()

        _ = sut.addGameDiceResult(data: data, name: "Alex", supporterTier: .none, isGameMaster: false, senderId: first)
        _ = sut.addGameDiceResult(data: data, name: "Alex", supporterTier: .none, isGameMaster: false, senderId: second)

        #expect(sut.diceGameModel.playerDice.count == 2)
        let senders = Set(sut.sharedPlayerDice.compactMap { sut.playerDiceSenderId(for: $0.id) })
        #expect(senders == [first, second])

        // The same device rolling again replaces its own dice only.
        _ = sut.addGameDiceResult(data: data, name: "Alex", supporterTier: .none, isGameMaster: false, senderId: first)
        #expect(sut.diceGameModel.playerDice.count == 2)
        #expect(Set(sut.sharedPlayerDice.compactMap { sut.playerDiceSenderId(for: $0.id) }) == [first, second])

        // Without a sender (a proxy's own rolls) the name still identifies the player.
        _ = sut.addGameDiceResult(data: data, name: "Host", supporterTier: .none, isGameMaster: false)
        _ = sut.addGameDiceResult(data: data, name: "Host", supporterTier: .none, isGameMaster: false)
        #expect(sut.diceGameModel.playerDice.filter { $0.name == "Host" }.count == 1)

        sut.diceGameModel.reset()
        #expect(sut.diceGameModel.playerDiceSenders.isEmpty)
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
    
    /// CODE_AUDIT_26 §3.1: the category of a share is exported with that share only. Two shares of
    /// one dice in flight at once each carry their own category and the stored one is untouched.
    @Test func overlappingSharesExportTheirOwnResultCategory() async throws {
        let (root, dice) = await GameControllerTests.setupDice()
        let sut = root.gameController
        let stored = dice.resultCategory
        let first = ResultCategory(id: UUID(), module: .table)
        let second = ResultCategory(id: UUID(), module: .pdf)

        async let firstData = sut.createGameData(for: dice.id, resultCategory: first)
        async let secondData = sut.createGameData(for: dice.id, resultCategory: second)
        let (firstShare, secondShare) = try await (firstData, secondData)
        #expect(dice.resultCategory == stored)

        let receiver = DiceRootModel.testRoot()
        await receiver.itemController.resetData()
        await receiver.gameController.reset()
        try await receiver.gameController.updateGame(data: firstShare, hide: false, focus: false)
        #expect(receiver.gameController.gameItem(for: dice.id).resultCategory == first)
        try await receiver.gameController.updateGame(data: secondShare, hide: false, focus: false)
        #expect(receiver.gameController.gameItem(for: dice.id).resultCategory == second)
        #expect(dice.resultCategory == stored)
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
    
    @Test func compareOptionDecidesTheCheckWithoutAddDice() async throws {
        let (root, dice) = await GameControllerTests.setupDice()
        let sut = root.gameController
        let item = sut.gameItem(for: dice.id)
        item.addDiceEvery = 0
        item.sumUp = true
        item.modifier = 0
        item.coupValues = []
        item.fumbleValues = []
        item.rerollOptions = []
        item.compareOption = .lowerEqual
        item.compareValue = 15
        item.dice = [DieModel(id: GameControllerTests.dieUUID1, die: .twenty, rotation: 0, result: [12], displayState: 3)]
        #expect(sut.calculate(itemId: dice.id).checked)

        item.dice = [DieModel(id: GameControllerTests.dieUUID1, die: .twenty, rotation: 0, result: [18], displayState: 3)]
        #expect(!sut.calculate(itemId: dice.id).checked)

        item.compareOption = .equalHigher
        #expect(sut.calculate(itemId: dice.id).checked)

        // Without a compare option any positive sum is a success, as before.
        item.compareOption = .off
        #expect(sut.calculate(itemId: dice.id).checked)
    }

    @Test("A reset keeps both of two same-named players' dice when it names them by sender id (CODE_AUDIT_26 §5.17)")
    func resetKeepsNamesakesApart() async throws {
        let (root, dice) = await GameControllerTests.setupDice()
        let sut = root.gameController
        dice.dice = GameControllerTests.diceResult(values: [[2], [3], [4]])
        let data = await sut.createDiceResult(for: dice.id, resultCategory: nil)
        let alexA = UUID()
        let alexB = UUID()
        let leaver = UUID()
        _ = sut.addGameDiceResult(data: data, name: "Alex", supporterTier: .none, isGameMaster: false, senderId: alexA)
        _ = sut.addGameDiceResult(data: data, name: "Alex", supporterTier: .none, isGameMaster: false, senderId: alexB)
        _ = sut.addGameDiceResult(data: data, name: "Robin", supporterTier: .none, isGameMaster: false, senderId: leaver)
        let before = sut.diceGameModel.playerDice.map(\.id)
        #expect(before.count == 3)
        let leaverDie = try #require(sut.diceGameModel.playerDiceSenders.first { $0.value == leaver }?.key)

        sut.resetPlayerDice(keepingSenders: [alexA, alexB], names: ["Alex", "Alex"])

        let after = sut.diceGameModel.playerDice.map(\.id)
        #expect(Set(after).count == 2, "no die appears twice")
        #expect(Set(after) == Set(before).subtracting([leaverDie]))
        #expect(Set(sut.diceGameModel.playerDiceSenders.values) == [alexA, alexB])
        #expect(Set(sut.diceGameModel.playerSupporterTiers.keys) == Set(after))
    }

    @Test("A shared roll carries the dice but not the master's notes (CODE_AUDIT_26 §6.8)")
    func sharedRollDropsDescriptionTagsAndEntries() async throws {
        let (root, dice) = await GameControllerTests.setupDice()
        let sut = root.gameController
        dice.dice = GameControllerTests.diceResult(values: [[2], [3], [4]])
        dice.parentId = UUID()
        dice.entries = [ChildEntryModel(id: UUID(), childId: UUID())]

        let data = await sut.createDiceResult(for: dice.id, resultCategory: nil)
        let shared = try #require(DiceResultModel.decodeData(of: data.data))

        #expect(shared.diceModel.description_.wrappedValue.isEmpty)
        #expect(shared.diceModel.tags_.wrappedValue.isEmpty)
        #expect(shared.diceModel.entries_.wrappedValue.isEmpty)
        #expect(shared.diceModel.parentId == nil)
        // What a receiver needs stays.
        #expect(shared.diceModel.name_.wrappedValue == dice.name)
        #expect(shared.diceModel.dice.count == 3)
        #expect(shared.diceModel.compareOption == dice.compareOption)
        #expect(shared.diceModel.compareValue == dice.compareValue)
        #expect(shared.values == "2|3|4")
        // The game master's own copy keeps its notes.
        #expect(!sut.gameItem(for: dice.id).description.isEmpty)
        #expect(!sut.gameItem(for: dice.id).tags.isEmpty)
    }

    @Test("A roll without a known sender is kept by the player's name")
    func resetKeepsUnknownSenderByName() async throws {
        let (root, dice) = await GameControllerTests.setupDice()
        let sut = root.gameController
        dice.dice = GameControllerTests.diceResult(values: [[2], [3], [4]])
        let data = await sut.createDiceResult(for: dice.id, resultCategory: nil)
        _ = sut.addGameDiceResult(data: data, name: "Host", supporterTier: .none, isGameMaster: false)
        _ = sut.addGameDiceResult(data: data, name: "Gone", supporterTier: .none, isGameMaster: false, senderId: UUID())

        sut.resetPlayerDice(keepingSenders: [], names: ["Host"])

        #expect(sut.diceGameModel.playerDice.map(\.name) == ["Host"])
    }

    @Test("A roll without a category keeps the one the dice carries (CODE_AUDIT_26 §5.34)")
    func resultKeepsTheStoredCategory() async throws {
        let (root, dice) = await GameControllerTests.setupDice()
        let sut = root.gameController
        let characterCategory = ResultCategory(id: UUID(), module: .value)
        dice.dice = GameControllerTests.diceResult(values: [[2], [3], [4]])

        _ = await sut.createDiceResult(for: dice.id, resultCategory: characterCategory)
        let data = await sut.createDiceResult(for: dice.id, resultCategory: nil)

        #expect(sut.gameItem(for: dice.id).resultCategory == characterCategory)
        let shared = try #require(DiceResultModel.decodeData(of: data.data))
        #expect(shared.diceModel.resultCategory == characterCategory)
    }

    @Test("Rolling a library dice outside a game leaves its update marker alone (CODE_AUDIT_26 §5.35)")
    func rollKeepsTheUpdateMarker() async throws {
        let root = DiceRootModel.testRoot()
        await root.itemController.resetData()
        let sut = root.gameController
        let library = DiceModel(id: UUID(), name: "Library", dice: GameControllerTests.diceResult(values: [[], [], []]))
        root.itemController.replace(model: library, isInsert: true)
        let stored = try #require(root.itemController.itemSync(for: library.id))
        let marker = stored.dice_.update

        sut.rollDice(itemId: library.id, rollSynced: true)

        let rolled = try #require(root.itemController.itemSync(for: library.id))
        #expect(rolled.dice.allSatisfy { !$0.result.isEmpty }, "the roll happened")
        #expect(rolled.dice_.update == marker, "but it is not an edit")
        sut.reset(for: library.id)
        #expect(rolled.dice.allSatisfy { $0.result.isEmpty })
        #expect(rolled.dice_.update == marker)
    }

    @Test("A real edit of the dice still moves the marker")
    func editMovesTheMarker() {
        let model = DiceModel(id: UUID(), name: "Edited", dice: GameControllerTests.diceResult(values: [[], [], []]))
        let marker = model.dice_.update

        model.dice.removeLast()

        #expect(model.dice_.update != marker)
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
    
    /// CODE_AUDIT_19 §5.15: a "max dice value" reroll counts as the rerolled die's own maximum
    /// plus one. The second die used the first die's maximum, so a d6 rolled 1 next to a d20
    /// counted as 21 and sorted ahead of a d20 showing 10.
    @Test func reorderUsesEachDiesOwnMaximumForAReroll() async throws {
        let (root, dice) = await GameControllerTests.setupDice()
        let sut = root.gameController
        let sixId = UUID()
        let twentyId = UUID()
        dice.rerollOptions = [DiceModel.RerollOption(number: 1, value: 0, maxDiceValue: true)]
        dice.dice = [
            DieModel(id: sixId, die: .six, rotation: 0, result: [1], displayState: 3),
            DieModel(id: twentyId, die: .twenty, rotation: 0, result: [10], displayState: 3),
        ]
        #expect(sut.reorder(for: dice.id).map(\.id) == [twentyId, sixId])

        dice.dice = [
            DieModel(id: twentyId, die: .twenty, rotation: 0, result: [10], displayState: 3),
            DieModel(id: sixId, die: .six, rotation: 0, result: [1], displayState: 3),
        ]
        #expect(sut.reorder(for: dice.id).map(\.id) == [twentyId, sixId])
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
    
    @Test func roll() async throws {
        let (root, dice) = await GameControllerTests.setupDice()
        let sut = root.gameController

        dice.dice = GameControllerTests.diceResult(values: [[], [], []])
        sut.roll(die: dice.dice[0], for: dice.id)
        #expect(dice.dice.map { $0.result.count > 0 } == [true, false, false])
        sut.roll(die: dice.dice[1], for: dice.id)
        #expect(dice.dice.map { $0.result.count > 0 } == [true, true, false])
        sut.roll(die: dice.dice[2], for: dice.id)
        #expect(dice.dice.map { $0.result.count > 0 } == [true, true, true])
        dice.dice = GameControllerTests.diceResult(values: [[], [], []])
        sut.roll(die: nil, for: dice.id)
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

    // MARK: - Percent dice (CODE_AUDIT §5.16)

    @MainActor
    private static func percentDice(tens: Int, ones: Int, modifier: Double = 0, rerolls: [DiceModel.RerollOption] = []) -> DiceModel {
        DiceModel(
            id: UUID(),
            name: "Percent",
            description: "",
            tags: [],
            category: .item,
            displayState: 3,
            dice: [
                DieModel(id: dieUUID1, die: .ten, rotation: 0, result: [tens], displayState: 3),
                DieModel(id: dieUUID2, die: .ten, rotation: 0, result: [ones], displayState: 3)
            ],
            sumUp: true,
            modifier: modifier,
            percentDice: true,
            compareOption: .off,
            compareValue: 0,
            coupValues: [],
            coupOnlyOnFirstDie: false,
            fumbleValues: [],
            fumbleOnlyOnFirstDie: false,
            rerollOptions: rerolls,
            reorderDice: false,
            addDiceEvery: 0,
            resultCategory: ResultCategory(id: UUID(), module: .table)
        )
    }

    @Test("Percent dice add the modifier and stay within 1 to 100")
    @MainActor
    func percentDiceApplyModifierAndClamp() async {
        let root = DiceRootModel.testRoot()
        let sut = root.gameController

        #expect(sut.sumResult(of: Self.percentDice(tens: 3, ones: 4)) == 34)
        #expect(sut.sumResult(of: Self.percentDice(tens: 3, ones: 4, modifier: 10)) == 44)
        #expect(sut.sumResult(of: Self.percentDice(tens: 9, ones: 8, modifier: 10)) == 100, "clamped to 100")
        #expect(sut.sumResult(of: Self.percentDice(tens: 3, ones: 4, modifier: -50)) == 1, "clamped to 1")
        #expect(sut.sumResult(of: Self.percentDice(tens: 10, ones: 10)) == 100, "00 reads as 100")
    }

    @Test("Percent dice honour reroll overrides")
    @MainActor
    func percentDiceApplyRerollOverrides() async {
        let root = DiceRootModel.testRoot()
        let sut = root.gameController
        let reroll = DiceModel.RerollOption(number: 1, value: 5, maxDiceValue: false)

        // a rolled 1 on either die counts as 5
        #expect(sut.sumResult(of: Self.percentDice(tens: 1, ones: 1, rerolls: [reroll])) == 55)
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
            rerollOptions: [DiceModel.RerollOption(number: 1, value: 0, maxDiceValue: true)],
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
