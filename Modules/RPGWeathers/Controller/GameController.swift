// @copyright André Trettin

import AndrenalinKit
import Foundation
import Observation
import RPGPhotos

public protocol WeatherGameStorable {}

struct GameController: Sendable {
    @MainActor init(photoRoot: PhotoRootModel, itemController: ItemController, linkRegisterControllable: LinkRegisterControllable, rootExportControllable: any ExportControllable, rootImportControllable: any ImportControllable) {
        self.itemController = itemController
        self.exportController = ExportController(photoRoot: photoRoot, itemController: itemController, gameExporter: false)
        let internItemController = ItemController(dataController: nil, linkRegisterControllable: linkRegisterControllable)
        self.importController = ImportController(itemController: internItemController)
        self.rootExportControllable = rootExportControllable
        self.rootImportControllable = rootImportControllable
        self.gameModel = ItemGameModel(itemDataModel: internItemController.itemDataModel)
    }

    let itemController: ItemController
    let exportController: ExportController
    let importController: ImportController
    let rootExportControllable: any ExportControllable
    let rootImportControllable: any ImportControllable

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
}

extension GameController: WeatherGameStorable {}
