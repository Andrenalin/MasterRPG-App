// @copyright André Trettin

import CoreRPG
import Foundation
import os.log
import DiceRPG

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

    public func exportingAll() -> ItemModuleIds {
        var allIds = rootManager.diceRoot.exportControllable.exportingAll()
        allIds.merge(other: ItemModuleIds(dictionary: [itemController.config.module: itemController.itemDataModel.items.filter { itemController.itemSync(for: $0)?.displayState != 2 }]))

        return allIds
    }
    
    @MainActor public func exporting(itemIds: ItemModuleIds) -> ItemModuleIds {
        var checkIds = itemIds.ids[itemController.config.module, default: []]
        var results: Set<UUID> = []
        var diceIds: Set<UUID> = []
    
        while !checkIds.isEmpty {
            let id = checkIds.removeLast()
            guard let item = itemController.itemSync(for: id) else {
                Task {
                    await logExport(title: "exporting not found \(id.uuidString))", count: 1)
                }
                continue
            }
            results.insert(id)
    
            if let diceId = item.diceId, rootManager.diceRoot.linkControllable.validateLink(itemId: diceId) {
                diceIds.insert(diceId)
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
            } else {
                let links = item.entries.flatMap { entry in
                    entry.links(for: entry.content)
                }
                
                links.forEach {
                    switch $0.module {
                    case .dice:
                        if rootManager.diceRoot.linkControllable.validateLink(itemId: $0.itemId) {
                            diceIds.insert($0.itemId)
                        }
                    case .table:
                        if !(results.contains($0.itemId) || checkIds.contains($0.itemId)) && itemController.itemSync(for: $0.itemId) != nil {
                            checkIds.append($0.itemId)
                        }
                    default:
                        Logger.exportController.error("Table \(item.name, privacy: .public) export is not handling link \($0.markDown, privacy: .public)")
                    }
                }
            }
        }
        var allIds = itemIds
        allIds.ids[itemController.config.module] = Array(results)

        let newDiceIds = rootManager.diceRoot.exportControllable.exporting(ids: diceIds)
        allIds.merge(other: newDiceIds)
        return allIds
    }
}
