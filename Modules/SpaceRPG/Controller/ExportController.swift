// @copyright André Trettin

import CoreRPG
import Foundation

struct ExportController: Sendable {
    @MainActor
    init(itemController: any OldItemControllable, fileController: FileController, gameExporter: Bool) {
        itemControllable = itemController
        fileControllable = fileController
        self.exportModel = ItemDataExportModel(gameExporter: gameExporter)
    }
    
    public let exportModel: ItemDataExportModel
    var fileControllable: (any FileControllable)?
    var itemControllable: any OldItemControllable

    var networkModule: NetworkModules { SpaceDataModel.typeId }
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
            
            let ids = item.entries.compactMap { entry -> UUID? in
                guard let entry = entry as? SpaceEntryDataModel, let subId = entry.childId else { return nil }
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
