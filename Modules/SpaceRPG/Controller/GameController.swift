// @copyright André Trettin

import CoreRPG
import Foundation
import os.log

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
    init(itemController: ItemController, fileUrlDataController: FileUrlDataController) {
        self.itemController = itemController
        self.exportController = ExportController(module: itemController.module, itemController: itemController, fileUrlDataController: fileUrlDataController, gameExporter: false)
        let internItemController = ItemController(container: itemController.container, module: itemController.module)
        self.importController = ImportController(itemController: internItemController, fileUrlDataController: fileUrlDataController, module: itemController.module)
        self.gameModel = ItemGameModel()
        self.spaceGameModel = SpaceGameModel()
    }

    let itemController: ItemController
    let importController: ImportController
    let exportController: ExportController
    
    let gameModel: ItemGameModel
    let spaceGameModel: SpaceGameModel
}

extension GameController: GameControllable {
    var itemControllable: any ItemControllable {
        itemController as (any ItemControllable)
    }
    var exportControllable: any ExportControllable {
        exportController as ExportControllable
    }
    @MainActor var importControllable: any ImportControllable {
        importController as ImportControllable
    }
    
    func resetGameState() {
        spaceGameModel.reset()
    }
}
