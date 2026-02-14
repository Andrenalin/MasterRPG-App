// @copyright André Trettin

import CoreRPG
import Foundation

@MainActor @Observable
final class SpaceGameModel: Sendable {
    init() {}

    var openSpace: Bool = false
    
    func reset() {
        openSpace = false
    }
}

struct GameController: Sendable {
    @MainActor init(rootManager: RootManager, itemController: ItemController, exportController: ExportController) {
        self.itemController = itemController
        self.exportController = exportController

        self.gameModel = ItemGameModel(itemDataModel: itemController.itemDataModel)
        self.spaceGameModel = SpaceGameModel()
    }

    let itemController: ItemController
    let exportController: ExportController

    let gameModel: ItemGameModel
    let spaceGameModel: SpaceGameModel

    @MainActor func gameItem(for itemId: UUID) -> SpaceModel {
        (gameModel.itemData[itemId] as? SpaceModel) ?? itemController.itemOrEmpty(for: itemId)
    }
    
    @MainActor func setGame(item: ItemGameModel.ModelType, itemId: UUID) {
        if gameModel.items.firstIndex(where: { $0 == itemId }) != nil {
            gameModel.itemData[itemId] = item
        } else {
            gameModel.items.insert(itemId, at: 0)
            gameModel.itemData[itemId] = item
        }
    }
    
    @MainActor func currentItem() -> SpaceModel {
        gameItem(for: gameModel.currentItemId ?? UUID())
    }
}

extension GameController: GameControllable {
    var itemControllable: any ItemControllable { itemController as (any ItemControllable) }
    var exportControllable: any ExportControllable { exportController as ExportControllable }

    @MainActor func resetGameState() {
        spaceGameModel.reset()
    }
}
