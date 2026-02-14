// @copyright André Trettin

import CoreRPG
import Foundation
import PhotoRPG

struct ExportController: Sendable {
    @MainActor init(rootManager: RootManager, itemController: ItemController) {
        self.rootManager = rootManager
        self.itemController = itemController
        self.exportModel = ItemDataExportModel()
    }

    let rootManager: RootManager
    let itemController: ItemController
    public let exportModel: ItemDataExportModel
}

extension ExportController: ExportControllable {
    var itemControllable: any ItemControllable { itemController }

    @MainActor public func exportingAll() -> ItemModuleIds {
        var allIds = rootManager.photoRoot.exportControllable.exportingAll()
        allIds.merge(other: ItemModuleIds(dictionary: [itemController.config.module: itemController.itemDataModel.items.map { $0 }]))
        return allIds
    }

    @MainActor public func exporting(itemIds: ItemModuleIds) -> ItemModuleIds {
        let checkIds = itemIds.ids[itemController.config.module, default: []]
        let results = checkIds.compactMap { itemController.itemSync(for: $0)?.id }
        var allIds = itemIds
        allIds.ids[itemController.config.module] = results

        let photoIds = Set(results.compactMap { itemController.itemSync(for: $0)?.photoId })
        let newPhotoIds = rootManager.photoRoot.exportControllable.exporting(ids: photoIds)
        allIds.merge(other: newPhotoIds)

        return allIds
    }
}
