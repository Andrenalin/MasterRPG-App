// @copyright André Trettin

import AndrenalinKit
import Foundation
import RPGPhotos

struct ExportController: Sendable {
    @MainActor init(photoRoot: PhotoRootModel, itemController: ItemController, gameExporter: Bool) {
        self.photoRoot = photoRoot
        self.itemController = itemController
        self.exportModel = ItemDataExportModel(gameExporter: gameExporter)
    }
    
    let photoRoot: PhotoRootModel
    let itemController: ItemController
    public let exportModel: ItemDataExportModel
}

extension ExportController: ExportControllable {
    var itemControllable: any ItemControllable {
        itemController
    }

    @MainActor public func exportingAll() -> ItemModuleIds {
        var allIds = photoRoot.exportControllable.exportingAll()
        allIds.merge(other: ItemModuleIds(dictionary: [itemController.itemDataModel.networkModule: itemController.itemDataModel.items.map { $0 }]))
        return allIds
    }

    @MainActor public func exporting(itemIds: ItemModuleIds) -> ItemModuleIds {
        let checkIds = itemIds.ids[itemController.itemDataModel.networkModule, default: []]
        let results = checkIds.compactMap { itemController.itemSync(for: $0)?.id }
        var allIds = itemIds
        allIds.ids[itemController.itemDataModel.networkModule] = results

        let photoIds = Set(results.compactMap { itemController.itemSync(for: $0)?.photoId })
        let newPhotoIds = photoRoot.exportControllable.exporting(ids: photoIds)
        allIds.merge(other: newPhotoIds)

        return allIds
    }
}
