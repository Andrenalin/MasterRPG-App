// @copyright André Trettin

import CoreRPG
import Foundation
import Observation
import PhotoRPG

public protocol WeatherGameStorable {}

struct GameController: Sendable {
    @MainActor init(rootManager: RootManager, photoRoot: PhotoRootModel, itemController: ItemController, exportController: ExportController) {
        self.itemController = itemController
        self.exportController = exportController

        self.gameModel = ItemGameModel(itemDataModel: itemController.itemDataModel)
    }

    let itemController: ItemController
    let exportController: ExportController

    let gameModel: ItemGameModel

    @MainActor func gameItem(for itemId: UUID) -> WeatherModel {
        (gameModel.itemData[itemId] as? WeatherModel) ?? itemController.itemOrEmpty(for: itemId)
    }
    
    @MainActor func setGame(item: ItemGameModel.ModelType, itemId: UUID) {
        if gameModel.items.firstIndex(where: { $0 == itemId }) != nil {
            gameModel.itemData[itemId] = item
        } else {
            gameModel.items.insert(itemId, at: 0)
            gameModel.itemData[itemId] = item
        }
    }
    
    @MainActor func currentItem() -> WeatherModel {
        gameItem(for: gameModel.currentItemId ?? UUID())
    }
}

extension GameController: GameControllable {
    var itemControllable: any ItemControllable { itemController as (any ItemControllable) }
    var exportControllable: any ExportControllable { exportController as ExportControllable }
}

extension GameController: WeatherGameStorable {}
