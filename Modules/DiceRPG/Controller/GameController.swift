// @copyright André Trettin

import CoreRPG
import AVFoundation
import Foundation
import Observation
import RPGResources
#if !os(tvOS)
import WidgetKit
#endif

@MainActor @Observable
final class DiceGameModel: Sendable {
    init() {}
    
    let audioPlayer: AVPlayer = AVPlayer()
    var hiddenPlayers: [String] = []
    var playerDice: [DiceModel] = []
    var masterDiceName: String?
    
    func reset() {
        hiddenPlayers = []
        playerDice = []
        masterDiceName = nil
    }
}

public protocol DiceGameStorable {
    @MainActor func addGameDiceResult(data: NetworkCodableDataType, name: String, isGameMaster: Bool) -> (String?, ResultCategory?)
    func createGameData(for itemId: UUID, resultCategory: ResultCategory?) async throws -> NetworkCodableDataType
    @MainActor func createGameDice(for diceId: UUID, gameDiceId: UUID?) -> UUID
    @MainActor func setFocusDice(on diceId: UUID?)
    func updateGame(data: NetworkCodableDataType, hide: Bool, focus: Bool) async throws
    @MainActor func number(for diceId: UUID, result: String) -> Int
    @MainActor func validateForValue(diceId: UUID, compareValue: Int?)
    @MainActor func resetPlayerDice(to playerIds: [String])
}

struct GameController: Sendable {
    @MainActor init(itemController: ItemController, exportController: ExportController) {
        self.itemController = itemController
        self.exportController = exportController

        self.gameModel = ItemGameModel(itemDataModel: itemController.itemDataModel)
        self.diceGameModel = DiceGameModel()
    }

    let itemController: ItemController
    let exportController: ExportController

    let gameModel: ItemGameModel
    let diceGameModel: DiceGameModel
    
    @MainActor
    func gameItem(for itemId: UUID) -> DiceModel {
        (gameModel.itemData[itemId] as? DiceModel) ?? itemController.itemOrEmpty(for: itemId)
    }
    
    @MainActor
    func setGame(item: ItemGameModel.ModelType, itemId: UUID) {
        if gameModel.items.firstIndex(where: { $0 == itemId }) != nil {
            gameModel.itemData[itemId] = item
        } else {
            gameModel.items.insert(itemId, at: 0)
            gameModel.itemData[itemId] = item
        }
    }
}

extension GameController: GameControllable {    
    var itemControllable: any ItemControllable { itemController as (any ItemControllable) }
    var exportControllable: any ExportControllable { exportController as ExportControllable }

    @MainActor func resetGameState() {
        diceGameModel.reset()
    }
}

extension GameController: DiceGameStorable {
    @discardableResult @MainActor
    func addGameDiceResult(data: NetworkCodableDataType, name: String, isGameMaster: Bool) -> (String?, ResultCategory?) {
        guard let diceResult = DiceResultModel.decodeData(of: data.data) else { return (nil, nil) }
        let dice = diceResult.diceModel
        dice.id = UUID()
        dice.name = name
        dice.applyResult(text: diceResult.values)
        
        if let index = diceGameModel.playerDice.firstIndex(where: { $0.id == dice.id || $0.name == name }) {
            diceGameModel.playerDice[index] = dice
        } else {
            diceGameModel.playerDice.insert(dice, at: 0)
        }
        if let index = gameModel.items.firstIndex(where: { $0 == dice.id || (gameModel.itemData[$0] as? DiceModel)?.name == name }) {
            gameModel.items.remove(at: index)
        }
        gameModel.items.insert(dice.id, at: 0)
        gameModel.itemData[dice.id] = dice
        if isGameMaster {
            diceGameModel.masterDiceName = name
        }
        return (diceResult.values, dice.resultCategory)
    }
    
    @MainActor
    func createDiceResult(for itemId: UUID, resultCategory: ResultCategory? = nil) async -> NetworkCodableDataType {
        if gameModel.itemData[itemId] == nil, let model = await itemControllable.item(for: itemId) {
            gameModel.itemData[model.id] = model
            gameModel.items.insert(model.id, at: 0)
        }
        let item = gameItem(for: itemId)
        item.resultCategory = resultCategory
        let diceResult = result(itemId: itemId)
        return NetworkCodableDataType(id: itemId, type: .dice, version: 0, data: diceResult.encodeData())
    }
    
    func createGameData(for itemId: UUID, resultCategory: ResultCategory?) async throws -> NetworkCodableDataType {
        let saveTask = Task { @MainActor in
            let nilResult: ResultCategory? = nil
            guard let model = await itemControllable.item(for: itemId) as? DiceModel else { return nilResult }
            let oldResultCategory = model.resultCategory
            model.resultCategory = resultCategory
            return oldResultCategory
        }
        let oldResultCategory = await saveTask.value
        let result = try await createGameData(for: itemId)
        let restoreTask = Task { @MainActor in
            guard let model = await itemControllable.item(for: itemId) as? DiceModel else { return }
            model.resultCategory = oldResultCategory
        }
        let _ = await restoreTask.result
        return result
    }
    
    @MainActor
    func createGameDice(for diceId: UUID, gameDiceId: UUID?) -> UUID {
        if let gameDiceId, gameModel.itemData[gameDiceId] != nil {
            return gameDiceId
        }
        let dice = itemController.itemOrEmpty(for: diceId).copy()
        dice.category = .value
        dice.id = gameDiceId ?? UUID()
        setGame(item: dice, itemId: dice.id)
        return dice.id
    }
    
    @MainActor
    func setFocusDice(on diceId: UUID?) {
        Task {
            if let diceId {
                await focus(on: diceId)
            } else {
                let gameDice = DiceModel.empty(UUID())
                gameDice.dice.append(DieModel.die20)
                setGame(item: gameDice, itemId: gameDice.id)
                await focus(on: gameDice.id)
            }
        }
    }
    
    func updateGame(data: NetworkCodableDataType, hide: Bool, focus: Bool) async throws {
        try await updateGame(data: data, hide: hide, deep: false)
        if focus {
            let saveTask = Task { @MainActor in
                if let index = gameModel.focusItemIds.firstIndex(where: { $0 == data.id }) {
                    gameModel.focusItemIds.remove(at: index)
                }
                reset(for: data.id)
                gameModel.focusItemIds.insert(data.id, at: 0)
            }
            let _ = await saveTask.result
        }
    }
    
    @MainActor
    func number(for diceId: UUID, result: String) -> Int {
        let dice = gameItem(for: diceId)
        dice.applyResult(text: result)
        setGame(item: dice, itemId: dice.id)
        return sumResult(itemId: diceId)
    }
    
    @MainActor
    func validateForValue(diceId: UUID, compareValue: Int?) {
        guard let compareValue, compareValue > 0 else { return }
        let validatedCompareValue = Double(compareValue)
        let model = gameItem(for: diceId)
        guard model.category == .value, model.compareValue != validatedCompareValue else { return }
        model.compareValue = validatedCompareValue
    }
    
    @MainActor
    func resetPlayerDice(to playerNames: [String]) {
        diceGameModel.playerDice = playerNames.compactMap { name in
            diceGameModel.playerDice.first { $0.name == name }
        }
    }
}

// MARK: - Player Dice

extension GameController {
    @MainActor
    func canEditDice(itemId: UUID, isGameMode: Bool) -> Bool {
        !isGameMode || gameItem(for: itemId).category != .table
    }
    
    @MainActor
    func hasResults(itemId: UUID) -> Bool {
        !gameItem(for: itemId).dice.flatMap { $0.result }.isEmpty
    }
    
    @MainActor
    func isFocusedDice(itemId: UUID) -> Bool {
        gameModel.focusItemIds.contains(itemId)
    }
    
    @MainActor
    func isPlayerDice(itemId: UUID) -> Bool {
        gameModel.focusItemIds.isEmpty && gameModel.items.contains(where: { $0 == itemId })
    }
    
    @MainActor
    func isPlayerHidden(playerId: UUID) -> Bool {
        let name = gameItem(for: playerId).name
        return diceGameModel.hiddenPlayers.contains { $0 == name }
    }
    
    @MainActor
    func toggleHidden(playerId: UUID) async {
        let name = gameItem(for: playerId).name
        if let hiddenIndex = diceGameModel.hiddenPlayers.firstIndex(where: { $0 == name }) {
            diceGameModel.hiddenPlayers.remove(at: hiddenIndex)
        } else {
            diceGameModel.hiddenPlayers.append(name)
        }
    }
}

extension GameController {
    @MainActor
    func resetCompareValue(of itemId: UUID, value: Int) async {
        let item = gameItem(for: itemId).copy()
        guard item.compareValue != Double(value) else { return }
        item.compareValue = Double(value)
        item.id = UUID()
        setGame(item: item, itemId: item.id)
        await focus(on: [item.id])
    }
    
    @MainActor
    func remove(die: DieModel, from itemId: UUID) {
        let item = gameItem(for: itemId)
        guard let index = item.dice.firstIndex(where: { $0.id == die.id }) else { return }
        item.dice.remove(at: index)
    }
    
    @MainActor
    func rollDice(itemId: UUID, networkActions: NetworkActions? = nil, resultCategopry: ResultCategory? = nil, rollSynced: Bool = false) {
        reset(for: itemId)
        
        let rollFunction = {
            role(die: nil, for: itemId)
            
            if let networkActions {
                Task {
                    let sendedResult = resultCategopry ?? gameItem(for: itemId).resultCategory ?? ResultCategory(id: itemId, module: itemController.config.module)
                    let result = await createDiceResult(for: itemId, resultCategory: sendedResult)
                    networkActions.game(result, .generic, nil)
                }
            }
        }
        
        if rollSynced {
            rollFunction()
        } else {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.1))
                rollFunction()
            }
        }
    }
    
    @MainActor
    private func diceName(for itemId: UUID, isOne: Bool) -> String {
        if isOne || gameItem(for: itemId).dice.count == 1 {
            let result = RawDie.role(.number(9))
            switch result {
            case 1:
                return RPGResources.Resources.Dice.d20_1.rawValue
            case 2:
                return RPGResources.Resources.Dice.d20_2.rawValue
            case 3:
                return RPGResources.Resources.Dice.d20_3.rawValue
            case 4:
                return RPGResources.Resources.Dice.d20_4.rawValue
            case 5:
                return RPGResources.Resources.Dice.d20_5.rawValue
            case 6:
                return RPGResources.Resources.Dice.d20_6.rawValue
            case 7:
                return RPGResources.Resources.Dice.d20_7.rawValue
            case 8:
                return RPGResources.Resources.Dice.d20_8.rawValue
            default:
                return RPGResources.Resources.Dice.d20_9.rawValue
            }
        }
        let result = RawDie.role(.number(6))
        switch result {
        case 1:
            return RPGResources.Resources.Dice.TwoD20_1.rawValue
        case 2:
            return RPGResources.Resources.Dice.TwoD20_2.rawValue
        case 3:
            return RPGResources.Resources.Dice.TwoD20_3.rawValue
        case 4:
            return RPGResources.Resources.Dice.TwoD20_4.rawValue
        case 5:
            return RPGResources.Resources.Dice.TwoD20_5.rawValue
        default:
            return RPGResources.Resources.Dice.TwoD20_6.rawValue
        }
    }
}

// MARK: - Dice Result

extension GameController {
    @MainActor
    func calculate(itemId: UUID) -> DiceResultModel {
        let item = gameItem(for: itemId)
        var result = DiceResultModel(diceModel: item)
        guard item.dice.reduce(0, { $0 + $1.result.count }) > 0 else { return result }
        
        result.result = .rolled
        let text = item.dice.compactMap {
            guard !$0.result.isEmpty else { return nil }
            return $0.result.map { "\($0)" }.joined(separator: ",")
        }.joined(separator: "|")
        result.values = text
        
        let succeed = !fumble(for: itemId)
        guard succeed else {
            result.result = .fumble
            return result
        }
        let sumResult = sumResult(itemId: itemId)
        result.sum = sumResult

        result.checked = sumResult > 0

        if coup(for: itemId) {
            result.result = .coup
        }
        
        return result
    }
    
    @MainActor
    func sumResult(itemId: UUID) -> Int {
        let item = gameItem(for: itemId)
        let orderedDice = reorder(for: itemId)
        var result = 0
        if item.sumUp {
            if item.canPercentDice, item.percentDice {
                var ten = orderedDice[0].result.last ?? 0
                var one = orderedDice[1].result.last ?? 0
                ten = ten == 10 ? 0 : ten
                one = one == 10 ? 0 : one
                result = ten * 10 + one
                if result == 0 {
                    result = 100
                }
            } else {
                orderedDice.enumerated().forEach { index, die in
                    let maxValue = maxValuePerDice(for: index + 1, itemId: itemId)
                    die.result.forEach { diceValue in
                        var value: Int
                        if let rerole = item.rerollOptions.first(where: { $0.number == diceValue }) {
                            value = rerole.maxDiceValue ? maxValue : rerole.value
                        } else {
                            if diceValue <= maxValue {
                                value = diceValue
                            } else {
                                value = 0
                            }
                        }
                        result += value
                    }
                }
                result += Int(item.modifier)
            }
        }
        return result
    }
    
    @MainActor
    func coup(for itemId: UUID) -> Bool {
        let item = gameItem(for: itemId)
        let allResults = item.coupOnlyOnFirstDie ? [item.dice.first?.result.first ?? 0] : item.dice.compactMap { $0.result.first }
        let coup = allResults.contains(where: { value in item.coupValues.contains(where: { $0.isDiceValue(value) }) })
        if coup { return true }
        let result = allResults.reduce(0) { $0 + $1 }
        return item.coupValues.contains(where: { $0.isResultValue(result) })
    }
    
    @MainActor
    func diceSuccess(for itemId: UUID) -> [(UUID, [Bool])] {
        let item = gameItem(for: itemId)
        guard item.dice.reduce(0, { $0 + $1.result.count }) > 0,
              !fumble(for: itemId),
              item.sumUp else { return [] }
        let orderedDice = reorder(for: itemId)
        if item.canPercentDice, item.percentDice {
            return orderedDice.map { ($0.id, [true]) }
        }
        return orderedDice.enumerated().map { index, die in
            let maxValue = maxValuePerDice(for: index + 1, itemId: itemId)
            let dieResult = die.result.map { diceValue in
                var value: Int
                if let rerole = item.rerollOptions.first(where: { $0.number == diceValue }) {
                    value = rerole.maxDiceValue ? maxValue : rerole.value
                } else {
                    if diceValue <= maxValue {
                        value = diceValue
                    } else {
                        value = 0
                    }
                }
                return value > 0
            }
            return (die.id, dieResult)
        }
    }
    
    @MainActor
    func fumble(for itemId: UUID) -> Bool {
        let item = gameItem(for: itemId)
        let allResults = item.fumbleOnlyOnFirstDie ? [item.dice.first?.result.first ?? 0] : item.dice.compactMap { $0.result.first }
        let fumble = allResults.contains(where: { value in item.fumbleValues.contains(where: { $0.isDiceValue(value) }) })
        if fumble { return true }
        let result = allResults.reduce(0) { $0 + $1 }
        return item.fumbleValues.contains(where: { $0.isResultValue(result) })
    }
    
    @MainActor
    func maxValuePerDice(for index: Int, itemId: UUID) -> Int {
        let item = gameItem(for: itemId)
        let maxDieValue = item.dice.first?.die.max ?? 1
        guard item.addDiceEvery > 0 else { return maxDieValue }
        let maxValue = Int(item.compareValue)
        return max(0, min((maxValue + maxDieValue) - item.addDiceEvery * index, maxDieValue))
    }
    
    @MainActor
    func result(itemId: UUID) -> DiceResultModel {
        calculate(itemId: itemId)
    }
    
    @MainActor
    func resultText(itemId: UUID) -> String {
        let diceResult = result(itemId: itemId)
        guard diceResult.result != .notRolled else { return String(localized: diceResult.result.localizedTitle).localizedString }
        let item = gameItem(for: itemId)
        var compareText = ""
        if item.compareOption != .off {
            compareText = "\(item.compareOption.rawText)\(Int(item.compareValue))"
        }
        var text = "\(diceResult.values)\(compareText)"
        var specialText = ""
        if diceResult.result == .coup || diceResult.result == .fumble {
            specialText = " \(String(localized: diceResult.result.localizedTitle).localizedString)"
        }
        if diceResult.result == .fumble {
            text += specialText
        } else {
            text += " ∑\(diceResult.sum)\(specialText)"
        }
        if item.compareOption != .off {
            text.append("\(diceResult.checked ? "✅" : "❌")")
        }
        return text
    }
    
    @MainActor
    func reorder(for itemId: UUID) -> [DieModel] {
        let item = gameItem(for: itemId)
        guard item.reorderDice else { return item.dice }
        let dice = item.dice.sorted {
            var first = $0.result.first ?? 0
            var second = $1.result.first ?? 0
            if let firstRerole = item.rerollOptions.first(where: { $0.number == first }) {
                if firstRerole.maxDiceValue {
                    first = $0.die.max + 1
                } else {
                    first = firstRerole.value
                }
            }
            if let secondRerole = item.rerollOptions.first(where: { $0.number == second }) {
                if secondRerole.maxDiceValue {
                    second = $0.die.max + 1
                } else {
                    second = secondRerole.value
                }
            }
            return first > second
        }
        return dice
    }
    
    @MainActor
    func reset(for itemId: UUID) {
        gameItem(for: itemId).dice = gameItem(for: itemId).dice.map { die in
            die.resetResults()
        }
    }
    
    @MainActor
    func role(die: DieModel?, for itemId: UUID) {
        if let dicePath = Resources.bundle.path(forResource: diceName(for: itemId, isOne: die != nil), ofType: "m4a") {
            let diceUrl = URL(fileURLWithPath: dicePath)
            let item = AVPlayerItem(url: diceUrl)
            diceGameModel.audioPlayer.replaceCurrentItem(with: item)
            diceGameModel.audioPlayer.play()
            diceGameModel.audioPlayer.volume = 0.33
        }
        
        let item = gameItem(for: itemId)
        if let die, let index = item.dice.firstIndex(where: { $0.id == die.id }) {
            gameItem(for: itemId).dice[index] = die.role(reroleOptions: item.rerollOptions)
        } else {
            gameItem(for: itemId).dice = gameItem(for: itemId).dice.map { die in
                die.role(reroleOptions: item.rerollOptions)
            }
        }
        Task {
            await diceUpdateWidget(diceResult: result(itemId: itemId))
        }
    }
    
    nonisolated private func diceUpdateWidget(diceResult: DiceResultModel) async {
#if !os(tvOS)
        // Update widget
        var config = DiceConfiguration.loadFromUserDefaults()
        config.lastRoll = diceResult
        config.selectedDice = diceResult.diceModel
        config.save()

        // Reload widgets
        WidgetCenter.shared.reloadAllTimelines()

        // Update Live Activity if game is active
        let defaults = UserDefaults(suiteName: UserDefaults.appGroupString)
        if defaults?.bool(forKey: "isGameActive") == true {
            await DiceRollerLiveActivityManager.shared.startOrUpdate(with: diceResult)
        }
#endif
    }
}
