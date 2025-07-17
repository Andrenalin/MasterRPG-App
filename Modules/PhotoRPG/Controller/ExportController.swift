// @copyright André Trettin

import CoreRPG
import Foundation

struct ExportController: Sendable {
    @MainActor
    init(itemController: any ItemControllable, fileController: FileController, gameExporter: Bool) {
        itemControllable = itemController
        fileControllable = fileController
        self.exportModel = ItemDataExportModel(gameExporter: gameExporter)
    }
    
    public let exportModel: ItemDataExportModel
    var fileControllable: (any FileControllable)?
    var itemControllable: any ItemControllable
    
    var networkModule: NetworkModules { .photo }
    var version: Int { 2024 }
}

extension ExportController: ExportControllable {
    
    @MainActor
    public func exporting(itemIds: ItemModuleIds) -> ItemModuleIds {
        var checkIds = itemIds.ids[networkModule, default: []]
        var results: Set<UUID> = []

        while !checkIds.isEmpty {
            let id = checkIds.removeLast()
            guard let item = itemControllable.itemSync(for: id) else {
                Task {
                    await logExport(title: "exporting not found \(id.uuidString))", count: 1)
                }
                continue
            }
            results.insert(id)
            
            let ids = item.entryModels.compactMap { entry -> UUID? in
                guard let entry = entry as? PhotoEntryDataModel, let subId = entry.photoId else { return nil }
                if !(results.contains(subId) || checkIds.contains(subId)) && itemControllable.itemSync(for: subId) != nil {
                    return subId
                }
                return nil
            }
            checkIds.append(contentsOf: ids)
        }
        var allIds = itemIds
        allIds.ids[networkModule] = Array(results)
        return allIds
    }
}
