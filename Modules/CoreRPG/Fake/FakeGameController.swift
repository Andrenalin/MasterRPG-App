// @copyright André Trettin

import Foundation

struct FakeGameController: GameControllable {
    @MainActor init(
        itemControllable: any ItemControllable = FakeItemController.fake,
        exportControllable: any ExportControllable = FakeExportController.fake,
        importControllable: any ImportControllable = FakeImportController.fake,
        gameModel: ItemGameModel = ItemGameModel(itemDataModel: ItemDataModel())
    ) {
        self.itemControllable = itemControllable
        self.exportControllable = exportControllable
        self.importControllable = importControllable
        self.gameModel = gameModel
    }
    
    var itemControllable: any ItemControllable
    var exportControllable: any ExportControllable
    var importControllable: any ImportControllable
    var gameModel: ItemGameModel
    
    @MainActor static let fake = FakeGameController()
}
