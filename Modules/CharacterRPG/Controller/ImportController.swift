// @copyright André Trettin

import CoreRPG
import Foundation

struct ImportController: Sendable {
    @MainActor init(itemController: ItemController) {
        self.itemController = itemController
        self.importModel = ItemDataImportModel()
    }
    
    let itemController: ItemController
    public let importModel: ItemDataImportModel
}

extension ImportController: ImportControllable {
    var itemControllable: any ItemControllable {
        itemController
    }
}

