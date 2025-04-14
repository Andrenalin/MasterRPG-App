// @copyright André Trettin

import AndrenalinKit
import Foundation
import os.log

struct ExportController: Sendable {
    @MainActor
    init(root: TableRoot, itemController: ItemController, gameExporter: Bool) {
        self.root = root
        self.itemController = itemController
        self.exportModel = ItemDataExportModel(gameExporter: gameExporter)
    }

    weak var root: TableRoot!
    let itemController: ItemController

    public let exportModel: ItemDataExportModel
}

extension ExportController: ExportControllable {
    var itemControllable: any ItemControllable {
        itemController as (any ItemControllable)
    }

    public func exportingAll() -> ItemModuleIds {
        var allIds = root.diceRoot.exportControllable.exportingAll()
        allIds.merge(other: ItemModuleIds(dictionary: [itemController.itemDataModel.networkModule: itemController.itemDataModel.items.map { $0 }]))
        return allIds
    }
    
    public func exporting(itemIds: ItemModuleIds) -> ItemModuleIds {
        var checkIds = itemIds.ids[itemController.itemDataModel.networkModule, default: []]
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
    
            if let diceId = item.diceId, root.diceRoot.linkController.validateLink(itemId: diceId) {
                diceIds.insert(diceId)
            }
    
            let links = item.entries.flatMap { entry in
                entry.links(for: entry.content)
            }
    
            links.forEach {
                switch $0.module {
                case .dice:
                    if root.diceRoot.linkController.validateLink(itemId: $0.itemId) {
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
        var allIds = itemIds
        allIds.ids[itemController.itemDataModel.networkModule] = Array(results)

        let newDiceIds = root.diceRoot.exportControllable.exporting(ids: diceIds)
        allIds.merge(other: newDiceIds)
        return allIds
    }
}
