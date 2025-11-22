// @copyright André Trettin

import AndrenalinKit
import Foundation

struct GameController: Sendable {
    @MainActor init(itemController: ItemController, linkRegisterControllable: LinkRegisterControllable, rootExportControllable: any ExportControllable, rootImportControllable: any ImportControllable) {
        self.itemController = itemController
        self.exportController = ExportController(itemController: itemController, gameExporter: false)
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
    func gameItem(for itemId: UUID) -> PdfModel {
        (gameModel.itemData[itemId] as? PdfModel) ?? itemController.itemOrEmpty(for: itemId)
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
    func currentItem() -> PdfModel {
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

extension GameController {}
