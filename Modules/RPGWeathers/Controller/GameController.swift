// @copyright André Trettin

import AndrenalinKit
import Foundation
import Observation

public protocol WeatherGameStorable {}

struct GameController: Sendable {
    @MainActor
    init(root: WeatherRoot, itemController: ItemController) {
        self.root = root
        self.itemController = itemController
        self.exportController = ExportController(root: root, itemController: itemController, gameExporter: false)
        let internItemController = ItemController(root: root, dataController: nil)
        self.importController = ImportController(root: root, itemController: internItemController, gameImporter: true)
        self.gameModel = ItemGameModel(itemDataModel: internItemController.itemDataModel)
    }

    weak var root: WeatherRoot!
    let itemController: ItemController
    let importController: ImportController
    let exportController: ExportController

    let gameModel: ItemGameModel

    @MainActor
    func gameItem(for itemId: UUID) -> WeatherModel {
        (gameModel.itemData[itemId] as? WeatherModel) ?? itemController.itemOrEmpty(for: itemId)
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
    func currentItem() -> WeatherModel {
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
        root.rootControllable.gameExportControllable
    }
    var rootImportControllable: any ImportControllable {
        root.rootControllable.gameImportControllable
    }
}

extension GameController: WeatherGameStorable {}
