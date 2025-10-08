// @copyright André Trettin

import Foundation

struct FakeGameController: GameControllable {
    
    @MainActor init(itemControllable: any ItemControllable, exportControllable: any ExportControllable, importControllable: any ImportControllable) {
        self.itemControllable = itemControllable
        self.exportControllable = exportControllable
        self.importControllable = importControllable
        self.gameModel = ItemGameModel()
    }
    
    let itemControllable: any ItemControllable
    var exportControllable: any ExportControllable
    @MainActor var importControllable: any ImportControllable
    var gameModel: ItemGameModel
}
