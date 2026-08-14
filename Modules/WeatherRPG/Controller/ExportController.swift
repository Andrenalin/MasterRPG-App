// @copyright André Trettin

import CoreRPG
import Foundation
import PhotoRPG

struct ExportController: Sendable {
    @MainActor init(photoRoot: PhotoRootModel, itemController: ItemController) {
        self.photoRoot = photoRoot
        self.itemController = itemController
        self.exportModel = ExportModel()
    }

    let exportModel: ExportModel
    let photoRoot: PhotoRootModel
    let itemController: ItemController
}

extension ExportController: ExportModelBacked {
    var itemControllable: any ItemControllable { itemController }

    @MainActor public func exportingAll() -> ItemModuleIds {
        var allIds = photoRoot.exportControllable.exportingAll()
        allIds.merge(other: ItemModuleIds(dictionary: [itemController.config.module: itemController.itemDataModel.items.filter { itemController.itemSync(for: $0)?.displayState != 2 }]))
        return allIds
    }

    @MainActor public func exporting(itemIds: ItemModuleIds) -> ItemModuleIds {
        var photoIds: Set<UUID> = []

        let results = bfsExportResults(seedIds: itemIds.ids[itemController.config.module, default: []]) { id in
            guard let item = itemController.itemSync(for: id) else { return nil }

            if let photoId = item.photoId, photoRoot.linkControllable.validateLink(itemId: photoId) {
                photoIds.insert(photoId)
            }

            guard item.specialCategory else { return [] }
            return item.entries.compactMap { entryId in
                itemController.itemSync(for: entryId.childId) != nil ? entryId.childId : nil
            }
        }

        var allIds = finalizeExportResults(results, into: itemIds)
        let newPhotoIds = photoRoot.exportControllable.exporting(ids: photoIds)
        allIds.merge(other: newPhotoIds)
        return allIds
    }
}
