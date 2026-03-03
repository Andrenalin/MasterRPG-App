// @copyright André Trettin

import CoreRPG
import Foundation
import TableRPG
import PhotoRPG
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
        var allIds = rootManager.photoRoot.exportControllable.exportingAll()
        allIds.merge(other: rootManager.tableRoot.exportControllable.exportingAll())
        allIds.merge(other: ItemModuleIds(dictionary: [itemController.config.module: itemController.itemDataModel.items.map { $0 }]))
        return allIds
    }
    
    @MainActor public func exporting(itemIds: ItemModuleIds) -> ItemModuleIds {
        var checkIds = itemIds.ids[itemController.config.module, default: []]
        var results: Set<UUID> = []
        var diceIds: Set<UUID> = []
        var photoIds: Set<UUID> = []
        var pdfIds: Set<UUID> = []
        var tableIds: Set<UUID> = []

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
            
            if let photoId = item.photoId, rootManager.photoRoot.linkControllable.validateLink(itemId: photoId) {
                photoIds.insert(photoId)
            }
            photoIds.formUnion(item.photos.filter { rootManager.photoRoot.linkControllable.validateLink(itemId: $0) })
            
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
                
                var links: [LinkReplaceModel] = []
                item.entries.forEach { entry in
                    links.append(contentsOf: entry.links(for: entry.name))
                    links.append(contentsOf: entry.links(for: entry.value))
                    if let valueId = entry.valueId, !(results.contains(valueId) || checkIds.contains(valueId)) {
                        checkIds.append(valueId)
                    }
                    if let diceId = entry.diceId {
                        diceIds.insert(diceId)
                    }
                }
                
                links.forEach {
                    switch $0.module {
                    case .dice:
                        if rootManager.diceRoot.linkControllable.validateLink(itemId: $0.itemId) {
                            diceIds.insert($0.itemId)
                        }
                    case .pdf:
                        if rootManager.pdfRoot.linkControllable.validateLink(itemId: $0.itemId) {
                            pdfIds.insert($0.itemId)
                        }
                    case .photo:
                        if rootManager.photoRoot.linkControllable.validateLink(itemId: $0.itemId) {
                            photoIds.insert($0.itemId)
                        }
                    case .table:
                        if rootManager.tableRoot.linkControllable.validateLink(itemId: $0.itemId, entryId: nil) {
                            tableIds.insert($0.itemId)
                        }
                    case .value:
                        if !(results.contains($0.itemId) || checkIds.contains($0.itemId)) && itemController.itemSync(for: $0.itemId) != nil {
                            checkIds.append($0.itemId)
                        }
                    default:
                        print("*** ERROR table \(item.name) export is not handling link \($0)")
                    }
                }
            }
        }
        var allIds = itemIds
        allIds.ids[itemController.config.module] = Array(results)

        let newDiceIds = rootManager.diceRoot.exportControllable.exporting(ids: diceIds)
        allIds.merge(other: newDiceIds)

        let newPdfIds = rootManager.pdfRoot.exportControllable.exporting(ids: pdfIds)
        allIds.merge(other: newPdfIds)

        let newPhotoIds = rootManager.photoRoot.exportControllable.exporting(ids: photoIds)
        allIds.merge(other: newPhotoIds)

        let newTableIds =  rootManager.tableRoot.exportControllable.exporting(ids: tableIds)
        allIds.merge(other: newTableIds)

        return allIds
    }
}
