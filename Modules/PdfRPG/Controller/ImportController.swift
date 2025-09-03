// @copyright André Trettin

import CoreRPG
import Foundation

struct ImportController: Sendable {
    @MainActor
    init(itemController: ItemController, module: NetworkModules) {
        self.itemController = itemController
        self.module = module
        self.importModel = ItemDataImportModel()
    }
    
    let itemController: ItemController
    let module: NetworkModules
    let importModel: ItemDataImportModel
}

extension ImportController: ImportControllable {
    var itemControllable: any ItemControllable {
        itemController as (any ItemControllable)
    }
}
