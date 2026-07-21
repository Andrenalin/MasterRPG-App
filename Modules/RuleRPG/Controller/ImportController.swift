// @copyright André Trettin

import CoreRPG

struct ImportController: Sendable {
    @MainActor
    init(itemController: ItemController, editController: EditController) {
        self.itemController = itemController
        self.editController = editController
    }

    let itemController: ItemController
    let editController: EditController
}

extension ImportController: ImportControllable {
    var itemControllable: any ItemControllable { itemController }
    var editControllable: any EditControllable { editController }
}

