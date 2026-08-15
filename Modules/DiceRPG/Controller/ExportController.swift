// @copyright André Trettin

import CoreRPG
import Foundation

struct ExportController: Sendable {
    @MainActor init(itemController: ItemController) {
        self.itemController = itemController
        self.exportModel = ExportModel()
    }

    let exportModel: ExportModel
    let itemController: ItemController
}

// `exporting(itemIds:)` comes for free from `ExportModelBacked`'s default — this module has no
// per-item companion assets beyond its own item tree. See CODE_AUDIT §9.2.
extension ExportController: ExportModelBacked {
    var itemControllable: any ItemControllable { itemController }
}
