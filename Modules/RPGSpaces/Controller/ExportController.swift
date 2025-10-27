// @copyright André Trettin

import AndrenalinKit
import Foundation

struct ExportController: Sendable {
    @MainActor
    init(itemController: ItemController, gameExporter: Bool) {
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

    public func exporting(itemIds: ItemModuleIds) -> ItemModuleIds {
        var checkIds = itemIds.ids[itemController.itemDataModel.networkModule, default: []]
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
                let subId = entryId.spaceId
                if !(results.contains(subId) || checkIds.contains(subId)) && itemController.itemSync(for: subId) != nil {
                    return subId
                }
                return nil
            }
            checkIds.append(contentsOf: ids)
        }
        var allIds = itemIds
        allIds.ids[itemController.itemDataModel.networkModule] = Array(results)
        return allIds
    }
}
