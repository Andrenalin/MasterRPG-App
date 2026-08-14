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

extension ExportController: ExportModelBacked {
    var itemControllable: any ItemControllable { itemController }
    
    @MainActor public func exporting(itemIds: ItemModuleIds) -> ItemModuleIds {
        exportingSimpleEntries(itemIds: itemIds)
    }
}
