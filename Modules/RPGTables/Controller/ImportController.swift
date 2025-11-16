// @copyright André Trettin

import AndrenalinKit
import Foundation

struct ImportController: Sendable {
    @MainActor
    init(root: TableRootModel, itemController: ItemController, gameImporter: Bool) {
        self.root = root
        self.itemController = itemController
        self.importModel = ItemDataImportModel(gameImporter: gameImporter)
    }
    
    weak var root: TableRootModel!
    let itemController: ItemController
    public let importModel: ItemDataImportModel
}

extension ImportController: ImportControllable {
    var itemControllable: any ItemControllable {
        itemController as (any ItemControllable)
    }
}
