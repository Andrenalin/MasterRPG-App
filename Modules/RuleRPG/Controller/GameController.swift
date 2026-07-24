// @copyright André Trettin

import CoreRPG
import Foundation

struct GameController: Sendable {
    @MainActor
    init(itemController: ItemController, exportController: ExportController) {
        self.itemController = itemController
        self.exportController = exportController
        gameModel = ItemGameModel(itemDataModel: itemController.itemDataModel)
    }

    let itemController: ItemController
    let exportController: ExportController
    let gameModel: ItemGameModel

    @MainActor
    func gameItem(for itemId: UUID) -> RuleModel {
        (gameModel.itemData[itemId] as? RuleModel) ?? itemController.itemOrEmpty(for: itemId)
    }

    @MainActor
    func setGame(item: ItemGameModel.ModelType, itemId: UUID) {
        if gameModel.items.contains(itemId) {
            gameModel.itemData[itemId] = item
        } else {
            gameModel.items.insert(itemId, at: 0)
            gameModel.itemData[itemId] = item
        }
    }

    @MainActor
    func currentItem() -> RuleModel {
        gameItem(for: gameModel.currentItemId ?? UUID())
    }
}

extension GameController: GameControllable {
    var itemControllable: any ItemControllable { itemController }
    var exportControllable: any ExportControllable { exportController }
}

