// @copyright André Trettin

import CoreRPG
import AVFoundation
import Foundation
import RPGResources
import os.log

@MainActor @Observable
final class DiceGameModel: Sendable {
    init() {}
    
    var itemData: [UUID: DiceDataModel] = [:]
    
    let audioPlayer: AVPlayer = AVPlayer()
    var hiddenPlayers: [String] = []
    var playerDice: [DiceDataModel] = []
    var masterDiceName: String?
    
    func reset() {
        hiddenPlayers = []
        playerDice = []
        masterDiceName = nil
    }
}

public protocol DiceGameStorable: GameControllable {
    @MainActor func addGameDiceResult(data: NetworkCodableDataType, name: String, isGameMaster: Bool) -> (String?, ResultCategory?)
    func createGameData(for itemId: UUID, resultCategory: ResultCategory?) async throws -> NetworkCodableDataType
    @MainActor func createGameDice(for diceId: UUID, gameDiceId: UUID?) -> UUID
    @MainActor func setFocusDice(on diceId: UUID?)
    func updateGame(data: NetworkCodableDataType, hide: Bool, focus: Bool) async throws
    @MainActor func number(for diceId: UUID, result: String) -> Int
    @MainActor func validateForValue(diceId: UUID, compareValue: Int?)
    @MainActor func resetPlayerDice(to playerIds: [String])
    
    @MainActor func isPlayerDice(itemId: UUID) -> Bool
    @MainActor func canEditDice(itemId: UUID, isGameMode: Bool) -> Bool
    @MainActor func hasResults(itemId: UUID) -> Bool
    @MainActor func resetCompareValue(of itemId: UUID, value: Int) async
}

public struct GameController: Sendable {
    @MainActor
    init(itemController: ItemController) {
        self.itemController = itemController
        self.exportController = ExportController(module: itemController.module, itemController: itemController, gameExporter: false)
        let internItemController = ItemController(container: itemController.container, module: itemController.module)
        self.importController = ImportController(itemController: internItemController, module: itemController.module)
        self.gameModel = ItemGameModel()
        self.diceGameModel = DiceGameModel()
    }

    let itemController: ItemController
    let importController: ImportController
    let exportController: ExportController
    
    public let gameModel: ItemGameModel
    let diceGameModel: DiceGameModel
}

extension GameController: GameControllable {
    public var itemControllable: any ItemControllable {
        itemController as (any ItemControllable)
    }
    public var exportControllable: any ExportControllable {
        exportController as ExportControllable
    }
    @MainActor public var importControllable: any ImportControllable {
        importController as ImportControllable
    }
    
    @MainActor
    public func resetGameState() {
        diceGameModel.reset()
    }
}

extension GameController {
    @MainActor func diceModel(itemId: UUID) -> DiceModel? {
        guard let model = model(itemId: itemId) else { return nil }
        // here converter?
        return DiceModel.empty(itemId)
    }
    
    @MainActor func model(itemId: UUID) -> DiceDataModel? {
        if let model = diceGameModel.itemData[itemId] {
            return model
        }
        guard let item = gameItem(for: itemId), let model = try? itemController.decodedModel(codableModel: item) else { return nil }
        diceGameModel.itemData[itemId] = model
        return model
    }

    @MainActor func models(itemId: UUID) -> (ItemDataCodableModel, DiceDataModel)? {
        guard let item = gameItem(for: itemId), let model = model(itemId: itemId) else { return nil }
        return (item, model)
    }

    @MainActor func setGame(item: ItemDataCodableModel, model: DiceDataModel, itemId: UUID) {
        setGame(item: item, itemId: itemId)
        diceGameModel.itemData[itemId] = model
    }
}

extension GameController: DiceGameStorable {
    @discardableResult @MainActor
    public func addGameDiceResult(data: NetworkCodableDataType, name: String, isGameMaster: Bool) -> (String?, ResultCategory?) {
        guard let diceResult = DiceResultModel.decodeData(of: data.data) else { return (nil, nil) }
        var dice = diceResult.diceModel
//        dice.id = UUID()
//        dice.name = name
//        dice.applyResult(text: diceResult.values)
//        
//        if let index = diceGameModel.playerDice.firstIndex(where: { $0.id == dice.id || $0.name == name }) {
//            diceGameModel.playerDice[index] = dice
//        } else {
//            diceGameModel.playerDice.insert(dice, at: 0)
//        }
//        if let index = gameModel.items.firstIndex(where: { $0 == dice.id || (gameModel.itemData[$0] as? DiceModel)?.name == name }) {
//            gameModel.items.remove(at: index)
//        }
//        gameModel.items.insert(dice.id, at: 0)
//        gameModel.itemData[dice.id] = dice
//        if isGameMaster {
//            diceGameModel.masterDiceName = name
//        }
        return (diceResult.values, dice.resultCategory)
    }
    
    @MainActor
    func createDiceResult(for itemId: UUID, resultCategory: ResultCategory? = nil) async -> NetworkCodableDataType {
        if gameModel.itemData[itemId] == nil, let model = itemControllable.itemDataCodableModel(id: itemId) {
            gameModel.itemData[model.id] = model
            gameModel.items.insert(model.id, at: 0)
        }
        let item = gameItem(for: itemId)
        //item?.resultCategory = resultCategory
        //let diceResult = result(itemId: itemId)
        //return NetworkCodableDataType(id: itemId, type: .dice, version: 0, data: diceResult.encodeData())
        return NetworkCodableDataType(id: itemId, type: .dice, version: 0, data: nil)
    }
    
    public func createGameData(for itemId: UUID, resultCategory: ResultCategory?) async throws -> NetworkCodableDataType {
        let saveTask = Task { @MainActor in
            let nilResult: ResultCategory? = nil
            guard let model = await itemControllable.item(for: itemId) as? DiceModel else { return nilResult }
            let oldResultCategory = model.resultCategory
            //model.resultCategory = resultCategory
            return oldResultCategory
        }
        let oldResultCategory = await saveTask.value
        let result = try await createGameData(for: itemId)
        let restoreTask = Task { @MainActor in
            guard let model = await itemControllable.item(for: itemId) as? DiceModel else { return }
            //model.resultCategory = oldResultCategory
        }
        let _ = await restoreTask.result
        return result
    }
    
    @MainActor
    public func createGameDice(for diceId: UUID, gameDiceId: UUID?) -> UUID {
        if let gameDiceId, gameModel.itemData[gameDiceId] != nil {
            return gameDiceId
        }
        guard var item = itemController.itemDataCodableModel(id: diceId), let model = itemController.model(for: diceId) else { return diceId }
        item.id = gameDiceId ?? UUID()
        item.category = .value
        model.itemId = item.id
        setGame(item: item, model: model, itemId: item.id)
        return item.id
    }
    
    @MainActor
    public func setFocusDice(on diceId: UUID?) {
        Task {
            if let diceId {
                await focus(on: diceId)
            } else {
                let model = DiceDataModel.twenty
                let item = model.itemDataCodableModel
                setGame(item: item, model: model, itemId: model.itemId)
                await focus(on: model.itemId)
            }
        }
    }
    
    public func updateGame(data: NetworkCodableDataType, hide: Bool, focus: Bool) async throws {
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
    public func number(for diceId: UUID, result: String) -> Int {
        guard let (item, dice) = models(itemId: diceId) else { return 0 }
        dice.applyResult(text: result)
        setGame(item: item, model: dice, itemId: dice.itemId)
        return sumResult(itemId: diceId)
    }
    
    @MainActor
    public func validateForValue(diceId: UUID, compareValue: Int?) {
        guard let compareValue, compareValue > 0, let (item, model) = models(itemId: diceId) else { return }
        let validatedCompareValue = Double(compareValue)
        guard item.category == .value, model.compareValue != validatedCompareValue else { return }
        model.compareValue = validatedCompareValue
    }
    
    @MainActor
    public func resetPlayerDice(to playerNames: [String]) {
//        diceGameModel.playerDice = playerNames.compactMap { name in
//            diceGameModel.playerDice.first { $0.name == name }
//        }
    }
}

// MARK: - Player Dice

extension GameController {
    @MainActor
    public func canEditDice(itemId: UUID, isGameMode: Bool) -> Bool {
        !isGameMode || gameItem(for: itemId)?.category != .table
    }
    
    @MainActor public func hasResults(itemId: UUID) -> Bool {
        guard let model = model(itemId: itemId) else { return false }
        return !model.dice.flatMap { $0.result }.isEmpty
    }
    
    @MainActor
    func isFocusedDice(itemId: UUID) -> Bool {
        gameModel.focusItemIds.contains(itemId)
    }
    
    @MainActor
    public func isPlayerDice(itemId: UUID) -> Bool {
        gameModel.focusItemIds.isEmpty && gameModel.items.contains(where: { $0 == itemId })
    }
    
    @MainActor
    func isPlayerHidden(playerId: UUID) -> Bool {
        guard let name = gameItem(for: playerId)?.name.wrappedValue else { return false }
        return diceGameModel.hiddenPlayers.contains { $0 == name }
    }
    
    @MainActor
    func toggleHidden(playerId: UUID) async {
        guard let name = gameItem(for: playerId)?.name.wrappedValue else { return }
        if let hiddenIndex = diceGameModel.hiddenPlayers.firstIndex(where: { $0 == name }) {
            diceGameModel.hiddenPlayers.remove(at: hiddenIndex)
        } else {
            diceGameModel.hiddenPlayers.append(name)
        }
    }
}

extension GameController {
    @MainActor public func resetCompareValue(of itemId: UUID, value: Int) async {
        guard var (item, model) = models(itemId: itemId) else { return }
        guard model.compareValue != Double(value) else { return }
        model.compareValue = Double(value)
        model.itemId = UUID()
        item.id = model.itemId
        setGame(item: item, model: model, itemId: item.id)
        await focus(on: [item.id])
    }
    
    @MainActor
    func remove(die: DieModel, from itemId: UUID) {
        guard let model = model(itemId: itemId), let index = model.dice.firstIndex(where: { $0.id == die.id }) else { return }
        model.dice.remove(at: index)
    }
    
    @MainActor
    func rollDice(itemId: UUID, networkActions: NetworkActions? = nil, resultCategopry: ResultCategory? = nil, rollSynced: Bool = false) {
        reset(for: itemId)
        
        let rollFunction = {
            role(die: nil, for: itemId)
            
            if let networkActions {
                Task {
//                    let sendedResult = resultCategopry ?? gameItem(for: itemId).resultCategory ?? ResultCategory(id: itemId, module: itemController.module)
//                    let result = await createDiceResult(for: itemId, resultCategory: sendedResult)
//                    networkActions.game(result, .generic)
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
        if isOne || gameItem(for: itemId)?.entries.count == 1 {
            let result = RawDie.role(.number(9))
            switch result {
            case 1:
                return Resources.Dice.d20_1.rawValue
            case 2:
                return Resources.Dice.d20_2.rawValue
            case 3:
                return Resources.Dice.d20_3.rawValue
            case 4:
                return Resources.Dice.d20_4.rawValue
            case 5:
                return Resources.Dice.d20_5.rawValue
            case 6:
                return Resources.Dice.d20_6.rawValue
            case 7:
                return Resources.Dice.d20_7.rawValue
            case 8:
                return Resources.Dice.d20_8.rawValue
            default:
                return Resources.Dice.d20_9.rawValue
            }
        }
        let result = RawDie.role(.number(6))
        switch result {
        case 1:
            return Resources.Dice.TwoD20_1.rawValue
        case 2:
            return Resources.Dice.TwoD20_2.rawValue
        case 3:
            return Resources.Dice.TwoD20_3.rawValue
        case 4:
            return Resources.Dice.TwoD20_4.rawValue
        case 5:
            return Resources.Dice.TwoD20_5.rawValue
        default:
            return Resources.Dice.TwoD20_6.rawValue
        }
    }
}

// MARK: - Dice Result

extension GameController {
    @MainActor
    func calculate(itemId: UUID) -> DiceResultModel? {
        guard let model = model(itemId: itemId) else { return nil }
        var result = DiceResultModel(diceModel: model.codableModel)
        guard model.dice.reduce(0, { $0 + $1.result.count }) > 0 else { return result }
        
        result.result = .rolled
        let text = model.dice.compactMap {
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
        guard let model = model(itemId: itemId) else { return 0 }
        let orderedDice = reorder(for: itemId)
        var result = 0
        if model.sumUp {
            if model.canPercentDice, model.percentDice {
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
                        if let rerole = model.rerollOptions.first(where: { $0.number == diceValue }) {
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
                result += Int(model.modifier)
            }
        }
        return result
    }
    
    @MainActor
    func coup(for itemId: UUID) -> Bool {
        guard let model = model(itemId: itemId) else { return false }
        let allResults = model.coupOnlyOnFirstDie ? [model.dice.first?.result.first ?? 0] : model.dice.compactMap { $0.result.first }
        let coup = allResults.contains(where: { value in model.coupValues.contains(where: { $0.isDiceValue(value) }) })
        if coup { return true }
        let result = allResults.reduce(0) { $0 + $1 }
        return model.coupValues.contains(where: { $0.isResultValue(result) })
    }
    
    @MainActor
    func diceSuccess(for itemId: UUID) -> [(UUID, [Bool])] {
        guard let model = model(itemId: itemId), model.dice.reduce(0, { $0 + $1.result.count }) > 0,
              !fumble(for: itemId),
              model.sumUp else { return [] }
        let orderedDice = reorder(for: itemId)
        if model.canPercentDice, model.percentDice {
            return orderedDice.map { ($0.id, [true]) }
        }
        return orderedDice.enumerated().map { index, die in
            let maxValue = maxValuePerDice(for: index + 1, itemId: itemId)
            let dieResult = die.result.map { diceValue in
                var value: Int
                if let rerole = model.rerollOptions.first(where: { $0.number == diceValue }) {
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
        guard let model = model(itemId: itemId) else { return false }
        let allResults = model.fumbleOnlyOnFirstDie ? [model.dice.first?.result.first ?? 0] : model.dice.compactMap { $0.result.first }
        let fumble = allResults.contains(where: { value in model.fumbleValues.contains(where: { $0.isDiceValue(value) }) })
        if fumble { return true }
        let result = allResults.reduce(0) { $0 + $1 }
        return model.fumbleValues.contains(where: { $0.isResultValue(result) })
    }
    
    @MainActor
    func maxValuePerDice(for index: Int, itemId: UUID) -> Int {
        guard let model = model(itemId: itemId) else { return 0 }
        let maxDieValue = model.dice.first?.die.max ?? 1
        guard model.addDiceEvery > 0 else { return maxDieValue }
        let maxValue = Int(model.compareValue)
        return max(0, min((maxValue + maxDieValue) - model.addDiceEvery * index, maxDieValue))
    }
    
    @MainActor
    func result(itemId: UUID) -> DiceResultModel? {
        calculate(itemId: itemId)
    }
    
    @MainActor
    func resultText(itemId: UUID) -> String {
        guard let model = model(itemId: itemId), let diceResult = result(itemId: itemId), diceResult.result != .notRolled else { return String(localized: DiceResultModel.DiceResult.notRolled.localizedTitle).localizedString }
        var compareText = ""
        if model.compareOption != .off {
            compareText = "\(model.compareOption.rawText)\(Int(model.compareValue))"
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
        if model.compareOption != .off {
            text.append("\(diceResult.checked ? "✅" : "❌")")
        }
        return text
    }
    
    @MainActor
    func reorder(for itemId: UUID) -> [DieDataModel] {
        guard let model = model(itemId: itemId) else { return [] }
        guard model.reorderDice else { return model.dice }
        let dice = model.dice.sorted {
            var first = $0.result.first ?? 0
            var second = $1.result.first ?? 0
            if let firstRerole = model.rerollOptions.first(where: { $0.number == first }) {
                if firstRerole.maxDiceValue {
                    first = $0.die.max + 1
                } else {
                    first = firstRerole.value
                }
            }
            if let secondRerole = model.rerollOptions.first(where: { $0.number == second }) {
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
        guard let model = model(itemId: itemId) else { return }
        model.dice.forEach { die in
            die.resetResults()
        }
    }
    
    @MainActor
    func role(die: DieDataModel?, for itemId: UUID) {
        guard let item = model(itemId: itemId) else { return }
        if let dicePath = Resources.bundle.path(forResource: diceName(for: itemId, isOne: die != nil), ofType: "m4a", inDirectory: "Dice") {
            let diceUrl = URL(fileURLWithPath: dicePath)
            let item = AVPlayerItem(url: diceUrl)
            diceGameModel.audioPlayer.replaceCurrentItem(with: item)
            diceGameModel.audioPlayer.play()
            diceGameModel.audioPlayer.volume = 0.33
        }
        
        if let die {
            die.role(reroleOptions: item.rerollOptions)
        } else {
            item.dice.forEach { die in
                die.role(reroleOptions: item.rerollOptions)
            }
        }
    }
}

