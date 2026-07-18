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
    /// Creates an independent, memory-only Character instance for one battle
    /// combatant. Reusing a monster template therefore never aliases the values
    /// of another monster placed from the same template.
    @MainActor func createBattleCharacterCopy(for characterId: UUID) -> UUID?
    @MainActor func battleCharacterCopy(for gameCharacterId: UUID) -> ValueModel?
    /// Removes battle-only runtime Characters after their non-player
    /// combatants leave the encounter. Persistent templates are never touched.
    @MainActor func removeBattleCharacterCopies(_ gameCharacterIds: Set<UUID>)
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
        (gameModel.itemData[itemId] as? ValueModel) ?? itemController.itemOrEmpty(for: itemId)
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
        let entry = gameItem(for: itemId)[entryId]
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
        if let diceId = gameItem(for: itemId).diceId {
            return gameDiceId(itemId: itemId, diceId: diceId)
        }        
        guard let entry = gameItem(for: itemId).entries.first(where: { $0.diceId != nil }) else { return nil }
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
    public func createBattleCharacterCopy(for characterId: UUID) -> UUID? {
        guard let source = itemController.itemSync(for: characterId) else { return nil }
        let copy = source.duplicateWithoutCopy()
        // Battle clones are lookup-only runtime data. Do not add them to the
        // presented game item order: that would make the latest monster the
        // current Character whenever an encounter starts.
        gameModel.itemData[copy.id] = copy
        return copy.id
    }

    @MainActor
    public func battleCharacterCopy(for gameCharacterId: UUID) -> ValueModel? {
        gameModel.itemData[gameCharacterId] as? ValueModel
    }

    @MainActor
    public func removeBattleCharacterCopies(_ gameCharacterIds: Set<UUID>) {
        guard !gameCharacterIds.isEmpty else { return }
        let entryIds = gameCharacterIds.reduce(into: Set<UUID>()) { result, characterId in
            guard let character = gameModel.itemData[characterId] as? ValueModel else { return }
            result.formUnion(character.entries.map(\.id))
        }
        gameModel.items.removeAll { gameCharacterIds.contains($0) }
        for characterId in gameCharacterIds {
            gameModel.itemData[characterId] = nil
            gameDiceModel.gameEntryDiceId[characterId] = nil
            gameDiceModel.gameDiceId[characterId] = nil
        }
        for entryId in entryIds {
            gameDiceModel.gameEntryDiceId[entryId] = nil
            gameDiceModel.gameDiceId[entryId] = nil
        }
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
