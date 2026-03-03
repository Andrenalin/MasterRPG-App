// @copyright André Trettin

import CoreRPG
import Foundation

struct ImportController: Sendable {
    @MainActor init(itemController: ItemController, editController: EditController) {
        self.itemController = itemController
        self.editController = editController
        self.importModel = ItemDataImportModel()
    }
    
    let itemController: ItemController
    let editController: EditController
    public let importModel: ItemDataImportModel
}

extension ImportController: ImportControllable {
    var itemControllable: any ItemControllable { itemController }
    var editControllable: any EditControllable { editController }
}
