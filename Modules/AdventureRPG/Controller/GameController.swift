// @copyright André Trettin

import CoreRPG
import DiceRPG
import MapRPG
import Foundation
import os.log

public protocol AdventureStoreGameable: GameControllable {
    @MainActor func startGame(with id: UUID)
    @MainActor func resetGame()
    @MainActor func saveGame() -> (Task<Void, any Error>, URL)
}

struct GameController: Sendable {
    @MainActor
    init(root: RootManager, itemController: ItemController) {
        self.itemController = itemController
        
        self.exportController = ExportController(module: itemController.module, itemController: itemController, gameExporter: false)
        let internItemController = ItemController(container: itemController.container, module: itemController.module)
        self.importController = ImportController(itemController: internItemController, module: itemController.module)
        self.gameModel = ItemGameModel()
        self.root = root
    }

    let itemController: ItemController
    let importController: ImportController
    let exportController: ExportController
    
    let gameModel: ItemGameModel
    let root: RootManager
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
}

extension GameController: AdventureStoreGameable {
    @MainActor func startGame(with id: UUID) {
        Task {
            await focus(on: id)
        }
        root[.map]?.gameControllable.startGame(with: id)
    }

    @MainActor
    func resetGame() {
        Task {
            await reset()
            for module in [NetworkModules.audio, .dice, .map, .pdf, .photo, .space, .table, .value, .weather] {
                await root[module]?.gameControllable.reset()
            }
        }
    }

    @MainActor
    func saveGame() -> (Task<Void, any Error>, URL) {
        // save only the map state, later we could save more states
        let ids = root[.map]?.gameControllable.saveAll() ?? ItemModuleIds()
        let url = exportControllable.exportUrl(isSaveGame: true)
        return (exportControllable.createExport(itemIds: ids, into: url), url)
    }
}
