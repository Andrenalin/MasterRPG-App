// @copyright André Trettin

import AndrenalinKit
import Foundation

struct GameController: Sendable {
    @MainActor
    init(root: PdfRoot, itemController: ItemController) {
        self.root = root
        self.itemController = itemController
        self.exportController = ExportController(root: root, gameExporter: false)
        let internItemController = ItemController(root: root, dataController: nil)
        self.importController = ImportController(root: root, itemController: internItemController)
        self.gameModel = ItemGameModel(itemDataModel: internItemController.itemDataModel)
    }
    
    weak var root: PdfRoot!
    let itemController: ItemController
    let importController: ImportController
    let exportController: ExportController
    
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
    var rootExportControllable: any ExportControllable {
        root.rootControllable.gameExportControllable
    }
    var rootImportControllable: any ImportControllable {
        root.rootControllable.gameImportControllable
    }
}

extension GameController {}
