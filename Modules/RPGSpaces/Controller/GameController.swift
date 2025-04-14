// @copyright André Trettin

import AndrenalinKit
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
    @MainActor
    init(root: SpaceRoot, itemController: ItemController) {
        self.root = root
        self.itemController = itemController
        self.exportController = ExportController(root: root, gameExporter: false)
        let internItemController = ItemController(root: root, dataController: nil)
        self.importController = ImportController(root: root, itemController: internItemController)
        self.gameModel = ItemGameModel(itemDataModel: internItemController.itemDataModel)
        self.spaceGameModel = SpaceGameModel()
    }

    weak var root: SpaceRoot!
    let itemController: ItemController
    let importController: ImportController
    let exportController: ExportController

    let gameModel: ItemGameModel
    let spaceGameModel: SpaceGameModel

    @MainActor
    func gameItem(for itemId: UUID) -> SpaceModel {
        (gameModel.itemData[itemId] as? SpaceModel) ?? itemController.itemOrEmpty(for: itemId)
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
    func currentItem() -> SpaceModel {
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
    
    func resetGameState() {
        spaceGameModel.reset()
    }
}
