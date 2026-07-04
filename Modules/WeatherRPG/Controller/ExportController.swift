// @copyright André Trettin

import CoreRPG
import Foundation
import PhotoRPG

struct ExportController: Sendable {
    @MainActor init(rootController: any RootControllable, photoRoot: PhotoRootModel, itemController: ItemController) {
        self.rootController = rootController
        self.photoRoot = photoRoot
        self.itemController = itemController
    }

    let rootController: any RootControllable
    let photoRoot: PhotoRootModel
    let itemController: ItemController
}

extension ExportController: ExportControllable {
    var itemControllable: any ItemControllable { itemController }

    @MainActor public func exportingAll() -> ItemModuleIds {
        var allIds = photoRoot.exportControllable.exportingAll()
        allIds.merge(other: ItemModuleIds(dictionary: [itemController.config.module: itemController.itemDataModel.items.filter { itemController.itemSync(for: $0)?.displayState != 2 }]))
        return allIds
    }

    @MainActor public func exporting(itemIds: ItemModuleIds) -> ItemModuleIds {
        var checkIds = itemIds.ids[itemController.config.module, default: []]
        var results: Set<UUID> = []
        var photoIds: Set<UUID> = []
    
        while !checkIds.isEmpty {
            let id = checkIds.removeLast()
            guard let item = itemController.itemSync(for: id) else {
                Task {
                    await logExport(title: "exporting not found \(id.uuidString))", count: 1)
                }
                continue
            }
            results.insert(id)
    
            if let photoId = item.photoId, photoRoot.linkControllable.validateLink(itemId: photoId) {
                photoIds.insert(photoId)
            }
    
            if item.specialCategory {
                let ids = item.entries.compactMap { entryId -> UUID? in
                    let subId = entryId.childId
                    if !(results.contains(subId) || checkIds.contains(subId)) && itemController.itemSync(for: subId) != nil {
                        return subId
                    }
                    return nil
                }
                checkIds.append(contentsOf: ids)
            }
        }
        let partialFolderIds: Set<UUID> = exportingFolder(results: &results)
        var allIds = itemIds
        allIds.ids[itemController.config.module] = Array(results)
        allIds.mergePartial(ids: Array(partialFolderIds), for: itemController.config.module)

        let newPhotoIds = photoRoot.exportControllable.exporting(ids: photoIds)
        allIds.merge(other: newPhotoIds)
        return allIds
    }
}
