// @copyright André Trettin

import CoreRPG
import Foundation

struct ExportController: Sendable {
    @MainActor init(itemController: ItemController, gameExporter: Bool) {
        self.itemController = itemController
        self.exportModel = ItemDataExportModel(gameExporter: gameExporter)
    }
    
    let itemController: ItemController
    public let exportModel: ItemDataExportModel
}

extension ExportController: ExportControllable {
    var itemControllable: any ItemControllable {
        itemController
    }

    @MainActor public func exporting(itemIds: ItemModuleIds) -> ItemModuleIds {
        let checkIds = itemIds.ids[itemController.config.module, default: []]
        let results = checkIds.compactMap { itemController.itemSync(for: $0)?.id }
        var allIds = itemIds
        allIds.ids[itemController.config.module] = results
        return allIds
    }
}
