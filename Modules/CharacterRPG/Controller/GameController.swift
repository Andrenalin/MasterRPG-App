// @copyright André Trettin

import CoreRPG
import DiceRPG
import Foundation
import os.log
import PhotoRPG
import TableRPG

@MainActor @Observable
final class ValueGameModel: Sendable {
    init() {}

    var gameEntryDiceId: [UUID: UUID] = [:]
    var gameDiceId: [UUID: UUID] = [:]
    
    func resetGameDiceId(itemId: UUID, entryId: UUID) {
        gameEntryDiceId[entryId] = nil
    }
}

public protocol ValueGameStorable {
    @MainActor func focusDice(for itemId: UUID) -> UUID?
    @MainActor func imageIds(for id: UUID) -> [UUID]
    @MainActor func playerPinPhoto(for characterId: UUID) -> UUID?
    @MainActor func startGame(for id: UUID?) async
    func updatePlayer(data: NetworkCodableDataType) async throws
}

struct GameController: Sendable {
    @MainActor init(root: CharacterRootModel, diceRoot: DiceRootModel, photoRoot: PhotoRootModel, tableRoot: TableRootModel, itemController: ItemController, exportController: ExportController) {
        self.root = root
        self.diceRoot = diceRoot
        self.photoRoot = photoRoot
        self.tableRoot = tableRoot
        
        self.itemController = itemController
        self.exportController = exportController

        self.gameModel = ItemGameModel(itemDataModel: itemController.itemDataModel)
        self.gameDiceModel = ValueGameModel()
    }
    
    let root: CharacterRootModel
    let diceRoot: DiceRootModel
    let photoRoot: PhotoRootModel
    let tableRoot: TableRootModel
    
    let itemController: ItemController
    let exportController: ExportController

    let gameModel: ItemGameModel
    let gameDiceModel: ValueGameModel
    
    @MainActor func gameItem(for itemId: UUID) -> ValueModel {
        itemController.itemOrEmpty(for: itemId)
    }
    
    @MainActor func setGame(item: ItemGameModel.ModelType, itemId: UUID) {
        if gameModel.items.firstIndex(where: { $0 == itemId }) != nil {
            gameModel.itemData[itemId] = item
        } else {
            gameModel.items.insert(itemId, at: 0)
            gameModel.itemData[itemId] = item
        }
    }
    
    @MainActor func currentItem() -> ValueModel {
        gameItem(for: gameModel.currentItemId ?? UUID())
    }
}

// MARK: - Dice for the game

extension GameController {
    @MainActor
    func gameDiceId(itemId: UUID, entryId: UUID) -> UUID? {
        let entry = itemController.itemOrEmpty(for: itemId)[entryId]
        guard let diceId = entry.diceId else { return nil }
        guard entry.type == .number else { return diceId }
        let gameEntryDiceId = gameDiceModel.gameEntryDiceId[entryId]
        let gameDiceId: UUID?
        if gameEntryDiceId != diceId {
            // reset
            gameDiceModel.gameEntryDiceId[entryId] = diceId
            gameDiceId = nil
        } else {
            gameDiceId = gameDiceModel.gameDiceId[entryId]
        }
        let newDiceId = diceRoot.diceGameControllable.createGameDice(for: diceId, gameDiceId: gameDiceId)
        if gameDiceId != nil {
            return gameDiceId
        }
        gameDiceModel.gameDiceId[entryId] = newDiceId
        return newDiceId
    }

    
    @MainActor
    func gameDiceId(itemId: UUID, diceId: UUID) -> UUID? {
        let gameEntryDiceId = gameDiceModel.gameEntryDiceId[itemId]
        let gameDiceId: UUID?
        if gameEntryDiceId != diceId {
            // reset
            gameDiceModel.gameEntryDiceId[itemId] = diceId
            gameDiceId = nil
        } else {
            gameDiceId = gameDiceModel.gameDiceId[itemId]
        }
        let newDiceId = diceRoot.diceGameControllable.createGameDice(for: diceId, gameDiceId: gameDiceId)
        if gameDiceId != nil {
            return gameDiceId
        }
        gameDiceModel.gameDiceId[itemId] = newDiceId
        return newDiceId
    }
    
    @MainActor
    func resetGameDiceId(itemId: UUID, entryId: UUID) {
        gameDiceModel.resetGameDiceId(itemId: itemId, entryId: entryId)
    }
}

extension GameController: GameControllable {
    var itemControllable: any ItemControllable { itemController as (any ItemControllable) }
    var exportControllable: any ExportControllable { exportController as ExportControllable }
}

extension GameController: ValueGameStorable {
    @MainActor
    public func focusDice(for itemId: UUID) -> UUID? {
        if let diceId = itemController.itemOrEmpty(for: itemId).diceId {
            return gameDiceId(itemId: itemId, diceId: diceId)
        }        
        guard let entry = itemController.itemOrEmpty(for: itemId).entries.first(where: { $0.diceId != nil }) else { return nil }
        return gameDiceId(itemId: itemId, entryId: entry.id)
    }

    @MainActor
    public func imageIds(for id: UUID) -> [UUID] {
        gameItem(for: id).photos
    }

    @MainActor
    public func playerPinPhoto(for characterId: UUID) -> UUID? {
        guard let itemId = root.linkController.validate(id: characterId, isCharacter: true) else { return nil }
        return itemController.itemOrEmpty(for: itemId).photoId
    }

    @MainActor
    public func startGame(for id: UUID?) async {
        guard let characterId = root.linkController.validate(id: id) else { return }
        await focus(on: [characterId])
    }

    public func updatePlayer(data: NetworkCodableDataType) async throws {
        guard data.type == itemControllable.config.module,
              let encodedData = data.data
        else { throw ItemGameStorableError.wrongData }
        try await importNetwork(from: encodedData, forceSave: true)
    }
}
