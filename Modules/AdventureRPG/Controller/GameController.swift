// @copyright André Trettin

import CoreRPG
import Foundation
import Observation
import TableRPG
import SwiftUI
import MapRPG
import AudioRPG
import DiceRPG
import PdfRPG
import PhotoRPG
import SpaceRPG
import CharacterRPG
import WeatherRPG

public protocol AdventureStoreGameable {
    @MainActor func startGame(with id: UUID) async
    @MainActor func focusDice(for itemId: UUID) -> UUID?
    @MainActor func resetGame() async
    @MainActor func saveGame() -> ItemModuleIds
}

struct GameController: Sendable {
    @MainActor
    init(rootManager: RootManager, root: AdventureRootModel, itemController: ItemController, exportController: ExportController) {
        self.root = root
        self.itemController = itemController
        self.exportController = exportController
        self.gameModel = ItemGameModel(itemDataModel: itemController.itemDataModel)
    }
    
    let root: AdventureRootModel
    let itemController: ItemController
    let exportController: ExportController
    
    let gameModel: ItemGameModel
    
    @MainActor func gameItem(for itemId: UUID) -> AdventureModel {
        (gameModel.itemData[itemId] as? AdventureModel) ?? itemController.itemOrEmpty(for: itemId)
    }
    
    @MainActor func setGame(item: ItemGameModel.ModelType, itemId: UUID) {
        if gameModel.items.firstIndex(where: { $0 == itemId }) != nil {
            gameModel.itemData[itemId] = item
        } else {
            gameModel.items.insert(itemId, at: 0)
            gameModel.itemData[itemId] = item
        }
    }
    
    @MainActor
    func currentItem() -> AdventureModel {
        gameItem(for: gameModel.currentItemId ?? UUID())
    }
}

extension GameController: GameControllable {
    var itemControllable: any ItemControllable {
        itemController as (any ItemControllable)
    }
    var exportControllable: any ExportControllable {
        exportController as ExportControllable
    }
}

extension GameController: AdventureStoreGameable {
    @MainActor
    func startGame(with id: UUID) async {
        await focus(on: id)
        root.mapRoot.mapGameControllable.startGameAsMaster()
    }
    
    @MainActor public func focusDice(for itemId: UUID) -> UUID? {
        if let diceId = itemController.itemOrEmpty(for: itemId).diceId {
            let newDiceId = root.diceRoot.diceGameControllable.createGameDice(for: diceId, gameDiceId: nil)
            return newDiceId
        }
        return nil
    }

    @MainActor
    func resetGame() async {
        await reset()
        await root.audioRoot.gameControllable.reset()
        await root.diceRoot.gameControllable.reset()
        await root.mapRoot.gameControllable.reset()
        await root.pdfRoot.gameControllable.reset()
        await root.photoRoot.gameControllable.reset()
        await root.spaceRoot.gameControllable.reset()
        await root.tableRoot.gameControllable.reset()
        await root.characterRoot.gameControllable.reset()
        await root.weatherRoot.gameControllable.reset()
    }

    @MainActor
    func saveGame() -> ItemModuleIds {
        // save only the map state, later we could save more states
        root.mapRoot.mapGameControllable.saveAll()
    }
}
