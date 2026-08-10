// @copyright André Trettin

import CoreRPG
import Foundation

struct ExportController: Sendable {
    @MainActor init(itemController: ItemController) {
        self.itemController = itemController
        self.exportModel = ExportModel()
    }

    let exportModel: ExportModel
    var hubControllable: any RootExportControllable {
        get {
            guard let hub = exportModel.hubControllable else {
                preconditionFailure("PdfRPG export requires its Adventure export hub after setup.")
            }
            return hub
        }
        set { exportModel.hubControllable = newValue }
    }
    let itemController: ItemController
}

extension ExportController: ExportControllable {
    var itemControllable: any ItemControllable { itemController }
    
    @MainActor public func exporting(itemIds: ItemModuleIds) -> ItemModuleIds {
        let results = bfsExportResults(seedIds: itemIds.ids[itemController.config.module, default: []]) { id in
            guard let item = itemController.itemSync(for: id) else { return nil }
            guard item.specialCategory else { return [] }
            return item.entries.compactMap { entryId in
                itemController.itemSync(for: entryId.childId) != nil ? entryId.childId : nil
            }
        }
        return finalizeExportResults(results, into: itemIds)
    }
}
