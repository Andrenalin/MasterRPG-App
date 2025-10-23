// @copyright André Trettin

import AndrenalinKit
import Foundation

struct ImportController: Sendable {
    @MainActor
    init(root: SpaceRoot, itemController: ItemController) {
        self.root = root
        self.itemController = itemController
        self.importModel = ItemDataImportModel()
    }
    
    weak var root: SpaceRoot!
    let itemController: ItemController
    public let importModel: ItemDataImportModel
}

extension ImportController: ImportControllable {
    var itemControllable: any ItemControllable {
        itemController as (any ItemControllable)
    }
}
