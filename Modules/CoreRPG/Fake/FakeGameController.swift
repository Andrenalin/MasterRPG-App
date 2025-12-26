// @copyright André Trettin

import Foundation

struct FakeGameController: GameControllable {
    @MainActor init() {
        self.itemControllable = FakeItemController.fake
        self.exportControllable = FakeExportController.fake
        self.importControllable = FakeImportController.fake
        self.rootExportControllable = FakeExportController.fake
        self.rootImportControllable = FakeImportController.fake
        self.gameModel = ItemGameModel(itemDataModel: ItemDataModel(categoryTags: []))
    }
    
    var itemControllable: any ItemControllable
    var exportControllable: any ExportControllable
    var importControllable: any ImportControllable
    var rootExportControllable: any ExportControllable
    var rootImportControllable: any ImportControllable
    var gameModel: ItemGameModel
    
    @MainActor static let fake = FakeGameController()
}
