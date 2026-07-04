// @copyright André Trettin

import CoreRPG
import Foundation
import Observation

struct ExportController: Sendable {
    @MainActor init(rootController: any RootControllable, itemController: ItemController) {
        self.rootController = rootController
        self.itemController = itemController
    }

    let rootController: any RootControllable
    let itemController: ItemController
}

extension ExportController: ExportControllable {
    var itemControllable: any ItemControllable { itemController }

    @MainActor public func exporting(itemIds: ItemModuleIds) -> ItemModuleIds {
        var checkIds = itemIds.ids[itemController.config.module, default: []]
        var results: Set<UUID> = []

        while !checkIds.isEmpty {
            let id = checkIds.removeLast()
            guard let item = itemController.itemSync(for: id) else {
                Task {
                    await logExport(title: "exporting not found \(id.uuidString))", count: 1)
                }
                continue
            }
            results.insert(id)
            
            let ids = item.entries.compactMap { entryId -> UUID? in
                let subId = entryId.audioId
                if !(results.contains(subId) || checkIds.contains(subId)) && itemController.itemSync(for: subId) != nil {
                    return subId
                }
                return nil
            }
            checkIds.append(contentsOf: ids)
        }
        let partialFolderIds: Set<UUID> = exportingFolder(results: &results)
        var allIds = itemIds
        allIds.ids[itemController.config.module] = Array(results)
        allIds.mergePartial(ids: Array(partialFolderIds), for: itemController.config.module)
        return allIds
    }
}
