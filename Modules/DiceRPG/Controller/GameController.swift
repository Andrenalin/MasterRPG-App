// @copyright André Trettin

import CoreRPG
import AVFoundation
import Foundation
import Synchronization
import Observation
import os.log
import RPGResources

@MainActor @Observable
final class DiceGameModel {
    init() {}
    
    let audioPlayer: AVPlayer = AVPlayer()
    var hiddenPlayers: [String] = []
    var playerDice: [DiceModel] = []
    var playerSupporterTiers: [UUID: SupporterTier] = [:]
    var masterDiceName: String?

    /// Cancelled and replaced on every roll so a rapid sequence of rolls can't queue up
    /// out-of-order widget updates. See CODE_AUDIT §3.3.
    @ObservationIgnored
    var diceUpdateWidgetTask: Task<Void, Never>?
    /// The delayed roll each dice set waits on, so a second `rollDice` before it fires replaces
    /// it instead of adding a second result to every die. See CODE_AUDIT_23 §5.14.
    @ObservationIgnored
    var pendingRollTasks: [UUID: Task<Void, Never>] = [:]

    func reset() {
        // A roll still waiting out its delay must not fire into the next game.
        pendingRollTasks.values.forEach { $0.cancel() }
        pendingRollTasks = [:]
        hiddenPlayers = []
        playerDice = []
        playerSupporterTiers = [:]
        masterDiceName = nil
    }
}

public protocol DiceGameStorable: Sendable {
    @MainActor func addGameDiceResult(
        data: NetworkCodableDataType,
        name: String,
        supporterTier: SupporterTier,
        isGameMaster: Bool
    ) -> (String?, ResultCategory?)
    func createGameData(for itemId: UUID, resultCategory: ResultCategory?) async throws -> NetworkCodableDataType
    func createVirtualGameData(
        numberOfSides: Int,
        name: String,
        resultCategory: ResultCategory
    ) async throws -> NetworkCodableDataType
    @MainActor func createGameDice(for diceId: UUID, gameDiceId: UUID?) -> UUID
    @MainActor func setFocusDice(on diceId: UUID?) async
    func updateGame(data: NetworkCodableDataType, hide: Bool, focus: Bool) async throws
    
    @MainActor func number(for diceId: UUID, result: String) -> Int
    /// Rolls one die of a dice set the way the sheet does, and shares the result like a roll
    /// of the whole set. For a die tossed by hand on the 3D table; the sheet makes no sound for
    /// it. Returns the face the die shows, or `nil` if the set has no such die.
    @MainActor func rollDie(_ dieId: UUID, of diceId: UUID, networkActions: NetworkActions?) -> Int?
    /// Whether the dice overlay shows a result line for this dice set: one that sums up or
    /// compares.
    @MainActor func showsResult(for diceId: UUID) -> Bool
    /// The dice a player last shared, as the dice overlay lists them; `nil` if there are none
    /// or this device has hidden that player's dice.
    @MainActor func playerDiceId(named playerName: String) -> UUID?
    /// The dice every other player last shared, as the dice overlay lists them, hidden or not.
    @MainActor var sharedPlayerDice: [DiceModel] { get }
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
    
}

// gameItem(for:)/setGame(item:itemId:)/currentItem() come from
// ModuleGameControllable's default implementations — including
// currentItem(), which this bespoke copy previously omitted entirely.
// See CODE_AUDIT_Game §9.1.
extension GameController: ModuleGameControllable {}

extension GameController: GameControllable {
    var itemControllable: any ItemControllable { itemController as (any ItemControllable) }
    var exportControllable: any ExportControllable { exportController as ExportControllable }

    @MainActor func resetGameState() {
        diceGameModel.reset()
    }
}

extension GameController: DiceGameStorable {
    @discardableResult @MainActor
    func addGameDiceResult(
        data: NetworkCodableDataType,
        name: String,
        supporterTier: SupporterTier,
        isGameMaster: Bool
    ) -> (String?, ResultCategory?) {
        guard let diceResult = DiceResultModel.decodeData(of: data.data) else { return (nil, nil) }
        let dice = diceResult.diceModel.makeModel(withId: UUID())
        dice.name = name
        dice.applyResult(text: diceResult.values)
        
        if let index = diceGameModel.playerDice.firstIndex(where: { $0.id == dice.id || $0.name == name }) {
            let replacedId = diceGameModel.playerDice[index].id
            diceGameModel.playerSupporterTiers[replacedId] = nil
            diceGameModel.playerDice[index] = dice
        } else {
            diceGameModel.playerDice.insert(dice, at: 0)
        }
        diceGameModel.playerSupporterTiers[dice.id] = supporterTier
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
        let oldResultCategory = await applyResultCategory(resultCategory, for: itemId)
        let result = try await createGameData(for: itemId)
        await applyResultCategory(oldResultCategory, for: itemId)
        return result
    }

    @MainActor
    @discardableResult
    private func applyResultCategory(_ resultCategory: ResultCategory?, for itemId: UUID) -> ResultCategory? {
        guard let model = itemController.itemSync(for: itemId) else { return nil }
        let oldResultCategory = model.resultCategory
        model.resultCategory = resultCategory
        return oldResultCategory
    }

    func createVirtualGameData(
        numberOfSides: Int,
        name: String,
        resultCategory: ResultCategory
    ) async throws -> NetworkCodableDataType {
        let itemId = UUID()
        await createVirtualDiceModel(itemId: itemId, numberOfSides: numberOfSides, name: name, resultCategory: resultCategory)
        return try await createGameData(
            for: itemId,
            resultCategory: resultCategory
        )
    }

    @MainActor
    private func createVirtualDiceModel(itemId: UUID, numberOfSides: Int, name: String, resultCategory: ResultCategory) {
        let dice = DiceModel(
            id: itemId,
            name: name,
            category: .value,
            dice: [
                DieModel(
                    id: UUID(),
                    die: RawDie(.number(max(numberOfSides, 1)))
                )
            ],
            resultCategory: resultCategory
        )
        itemController.replaceForGame(
            model: dice,
            isInsert: true,
            policy: .memoryOnly
        )
    }
    
    @MainActor
    func createGameDice(for diceId: UUID, gameDiceId: UUID?) -> UUID {
        if let gameDiceId, gameModel.itemData[gameDiceId] != nil {
            return gameDiceId
        }
        let dice = itemController.itemOrEmpty(for: diceId).copy(withId: gameDiceId ?? UUID())
        dice.category = .value
        setGame(item: dice, itemId: dice.id)
        return dice.id
    }
    
    @MainActor func setFocusDice(on diceId: UUID?) async {
        if let diceId {
            await focus(on: diceId)
        } else {
            let gameDice = DiceModel.empty(UUID())
            gameDice.dice.append(DieModel.die20)
            setGame(item: gameDice, itemId: gameDice.id)
            await focus(on: gameDice.id)
        }
    }
    
    func updateGame(data: NetworkCodableDataType, hide: Bool, focus: Bool) async throws {
        try await updateGame(data: data, hide: hide, deep: false)
        if focus {
            await refocus(on: data.id)
        }
    }

    @MainActor
    private func refocus(on itemId: UUID) {
        if let index = gameModel.focusItemIds.firstIndex(where: { $0 == itemId }) {
            gameModel.focusItemIds.remove(at: index)
        }
        reset(for: itemId)
        gameModel.focusItemIds.insert(itemId, at: 0)
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
        let activeDiceIDs = Set(diceGameModel.playerDice.map(\.id))
        diceGameModel.playerSupporterTiers = diceGameModel.playerSupporterTiers.filter {
            activeDiceIDs.contains($0.key)
        }
    }
}

