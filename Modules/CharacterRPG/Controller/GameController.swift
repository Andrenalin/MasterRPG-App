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
    func addItem(id: UUID, data: NetworkCodableDataType, for characterId: UUID) async
    @MainActor func focusDice(for itemId: UUID) -> UUID?
    @MainActor func imageIds(for id: UUID) -> [UUID]
    @MainActor func playerPinPhoto(for characterId: UUID) -> UUID?
    @MainActor func startGame(for id: UUID?) async
    func updatePlayer(data: NetworkCodableDataType) async throws
    
    @MainActor func create(name: String, value: String, resultCategory: ResultCategory) -> NetworkCodableDataType
    func add(result: NetworkCodableDataType, for characterId: UUID?) async
}

struct GameController: Sendable {
    @MainActor init(rootManager: RootManager, root: CharacterRootModel, diceRoot: DiceRootModel, photoRoot: PhotoRootModel, tableRoot: TableRootModel, itemController: ItemController, exportController: ExportController) {
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
    public func addItem(id: UUID, data: NetworkCodableDataType, for characterId: UUID) async {
        let adventureValue: ValueModel?

        if let character = await MainActor.run(body: { () -> ValueModel? in
            guard let characterId = root.linkController.validate(id: characterId) else { return nil }
            return itemController.itemOrEmpty(for: characterId)
        }) {
            adventureValue = await adventureModel(for: character)
        } else {
            adventureValue = nil
        }
        guard let adventureValue else { return }
        
        let hasItem = await MainActor.run {
            itemController.itemDataModel.items.contains { $0 == id }
        }
        try? await updateGame(data: data, hide: false, deep: true)
        let valueId = await root.editController.duplicate(itemId: id, withCopy: false)
        if !hasItem {
            await root.editController.delete(itemId: id)
        }
        let entry = ValueEntryModel(id: UUID(), name: "", type: .text, value: "", valueId: valueId)
        await MainActor.run {
            root.editController.add(entry: entry, into: adventureValue.id)
        }
    }

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
        if let encodedData = data.data {
            try await importNetwork(from: encodedData, forceSave: true)
        } else {
            guard data.type == itemControllable.config.module else { throw ItemGameStorableError.wrongData }
        }
    }

    @MainActor
    func create(name: String, value: String, resultCategory: ResultCategory) -> NetworkCodableDataType {
        let entry = ValueEntryModel(id: UUID(), name: name, type: .text, value: value)
        let result = ValueResultModel(valueModels: [], valueEntryModels: [entry])
        return NetworkCodableDataType(id: UUID(), type: itemController.config.module, version: 0, data: result.encodeData())
    }

    @MainActor
    func create(name: String, description: String, entries: [(String, String)], resultCategory: ResultCategory) -> NetworkCodableDataType {

        let valueEntries = entries.map {
            ValueEntryModel(id: UUID(), name: $0.0, type: .text, value: $0.1)
        }

        let model = ValueModel(id: UUID(), name: name, description: description, category: .item, entries: valueEntries)

        let result = ValueResultModel(valueModels: [model], valueEntryModels: [])
        return NetworkCodableDataType(id: UUID(), type: itemController.config.module, version: 0, data: result.encodeData())
    }

    @MainActor func add(result: NetworkCodableDataType, for characterId: UUID?) async {
        guard let valueResult = ValueResultModel.decodeData(of: result.data) else { return }

        let adventureValue: ValueModel?

        if let characterId = root.linkController.validate(id: characterId) {
            let character = itemController.itemOrEmpty(for: characterId)
            adventureValue = await adventureModel(for: character)
        } else {
            adventureValue = nil
        }
        for valueModel in valueResult.valueModels {
            let model = valueModel.duplicateWithoutCopy()
            root.itemController.replace(model: model, isInsert: true)
            root.editController.add(model: model, into: adventureValue?.id)
        }
        guard let adventureValue else { return }
        for entryModel in valueResult.valueEntryModels {
            let entry = entryModel.duplicate()
            root.editController.add(entry: entry, into: adventureValue.id)
        }
    }

    @MainActor private func adventureModel(for character: ValueModel) async -> ValueModel {
        let name = String(localized: "Adventure", bundle: .module).localizedString
        if let adventureEntry = character.entries.first(where: { $0.name == name }), let adventureValueId = adventureEntry.valueId {
            return itemController.itemOrEmpty(for: adventureValueId)
        }
        let description = String(localized: "Items sent from the gamemaster", bundle: .module).localizedString
        let adventureValue = ValueModel(id: UUID(), name: name, description: description, tags: [name], category: .item, photoId: character.photoId, photos: character.photos)
        adventureValue.isGroupHiddenToggle.toggle()
        
        itemController.replace(model: adventureValue, isInsert: true)
        let entry = ValueEntryModel(id: UUID(), name: name, type: .text, isGenerator: false, value: description, diceId: nil, valueId: adventureValue.id)
        root.editController.add(entry: entry, into: character.id)
        return adventureValue
    }
}
