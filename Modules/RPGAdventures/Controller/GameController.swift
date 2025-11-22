// @copyright André Trettin

import AndrenalinKit
import Foundation
import Observation
import RPGTables
import SwiftUI
import RPGMaps
import RPGAudios
import RPGDie
import RPGPdfs
import RPGPhotos
import SpaceRPG
import RPGValues
import RPGWeathers

public protocol AdventureStoreGameable {
    @MainActor func startGame(with id: UUID)
    @MainActor func resetGame()
    @MainActor func saveGame() -> (Task<Void, any Error>, URL)
}

struct GameController: Sendable {
    @MainActor
    init(root: AdventureRootModel!, itemController: ItemController) {
        self.root = root
        self.itemController = itemController
        self.exportController = ExportController(root: root, itemController: itemController, gameExporter: false)
        let internItemController = ItemController(root: root, dataController: nil)
        self.importController = ImportController(root: root, itemController: internItemController, gameImporter: true)
        self.gameExportController = ExportController(root: root, itemController: internItemController, gameExporter: true)
        self.gameModel = ItemGameModel(itemDataModel: internItemController.itemDataModel)
    }
    
    weak var root: AdventureRootModel!
    let itemController: ItemController
    let importController: ImportController
    let exportController: ExportController
    let gameExportController: ExportController
    
    let gameModel: ItemGameModel
    
    @MainActor
    func gameItem(for itemId: UUID) -> AdventureModel {
        (gameModel.itemData[itemId] as? AdventureModel) ?? itemController.itemOrEmpty(for: itemId)
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
    var importControllable: any ImportControllable {
        importController as ImportControllable
    }
    var rootExportControllable: any ExportControllable {
        gameExportController as ExportControllable
    }
    var rootImportControllable: any ImportControllable {
        importController as ImportControllable
    }
}

extension GameController: AdventureStoreGameable {
    @MainActor
    func startGame(with id: UUID) {
        Task {
            await focus(on: id)
        }
        root.mapRoot.gameControllable.startGameAsMaster()
    }

    @MainActor
    func resetGame() {
        Task {
            await reset()
            await root.audioRoot.gameControllable.reset()
            await root.diceRoot.gameControllable.reset()
            await root.mapRoot.gameControllable.reset()
            await root.pdfRoot.gameControllable.reset()
            await root.photoRoot.gameControllable.reset()
            await root.spaceRoot.gameControllable.reset()
            await root.tableRoot.gameControllable.reset()
            await root.valueRoot.gameControllable.reset()
            await root.weatherRoot.gameControllable.reset()
        }
    }

    @MainActor
    func saveGame() -> (Task<Void, any Error>, URL) {
        // save only the map state, later we could save more states
        let ids = root.mapRoot.gameControllable.saveAll()
        let url = rootExportControllable.exportUrl(isSaveGame: true)
        return (rootExportControllable.createExport(itemIds: ids, into: url), url)
    }
}
