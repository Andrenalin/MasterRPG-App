// @copyright André Trettin

import AndrenalinKit
import Foundation

struct ExportController: Sendable {
    @MainActor
    init(root: PhotoRoot, gameExporter: Bool) {
        self.root = root
        self.exportModel = ItemDataExportModel(gameExporter: gameExporter)
    }
    
    weak var root: PhotoRoot!
    public let exportModel: ItemDataExportModel
}

extension ExportController: ExportControllable {
    var itemControllable: any ItemControllable {
        root.itemController as (any ItemControllable)
    }
    var fileControllable: (any FileControllable)? {
        root.fileController
    }

    @MainActor
    public func exporting(itemIds: ItemModuleIds) -> ItemModuleIds {
        var checkIds = itemIds.ids[root.itemController.itemDataModel.networkModule, default: []]
        var results: Set<UUID> = []

        while !checkIds.isEmpty {
            let id = checkIds.removeLast()
            guard let item = root.itemController.itemSync(for: id) else {
                Task {
                    await logExport(title: "exporting not found \(id.uuidString))", count: 1)
                }
                continue
            }
            results.insert(id)
            
            let ids = item.entries.compactMap { entryId -> UUID? in
                let subId = entryId.photoId
                if !(results.contains(subId) || checkIds.contains(subId)) && root.itemController.itemSync(for: subId) != nil {
                    return subId
                }
                return nil
            }
            checkIds.append(contentsOf: ids)
        }
        var allIds = itemIds
        allIds.ids[root.itemController.itemDataModel.networkModule] = Array(results)
        return allIds
    }
}
