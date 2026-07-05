// @copyright André Trettin

import CoreRPG
import Foundation
import PdfRPG
import TableRPG
import PhotoRPG
import DiceRPG

struct ExportController: Sendable {
    // `hubControllable` reaches Adventure's hub exporter (ExportControllable.hubControllable).
    // Every other export path below uses the narrow diceRoot/pdfRoot/photoRoot/tableRoot refs instead.
    @MainActor init(hubControllable: any RootExportControllable, diceRoot: DiceRootModel, pdfRoot: PdfRootModel, photoRoot: PhotoRootModel, tableRoot: TableRootModel, itemController: ItemController) {
        self.hubControllable = hubControllable
        self.diceRoot = diceRoot
        self.pdfRoot = pdfRoot
        self.photoRoot = photoRoot
        self.tableRoot = tableRoot
        self.itemController = itemController
    }

    let hubControllable: any RootExportControllable
    let diceRoot: DiceRootModel
    let pdfRoot: PdfRootModel
    let photoRoot: PhotoRootModel
    let tableRoot: TableRootModel
    let itemController: ItemController
}

extension ExportController: ExportControllable {
    var itemControllable: any ItemControllable { itemController }

    public func exportingAll() -> ItemModuleIds {
        var allIds = photoRoot.exportControllable.exportingAll()
        allIds.merge(other: tableRoot.exportControllable.exportingAll())
        allIds.merge(other: ItemModuleIds(dictionary: [itemController.config.module: itemController.itemDataModel.items.filter { itemController.itemSync(for: $0)?.displayState != 2 }]))
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
            
            if let diceId = item.diceId, diceRoot.linkControllable.validateLink(itemId: diceId) {
                diceIds.insert(diceId)
            }

            if let photoId = item.photoId, photoRoot.linkControllable.validateLink(itemId: photoId) {
                photoIds.insert(photoId)
            }
            photoIds.formUnion(item.photos.filter { photoRoot.linkControllable.validateLink(itemId: $0) })
            
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
                        if diceRoot.linkControllable.validateLink(itemId: $0.itemId) {
                            diceIds.insert($0.itemId)
                        }
                    case .pdf:
                        if pdfRoot.linkControllable.validateLink(itemId: $0.itemId) {
                            pdfIds.insert($0.itemId)
                        }
                    case .photo:
                        if photoRoot.linkControllable.validateLink(itemId: $0.itemId) {
                            photoIds.insert($0.itemId)
                        }
                    case .table:
                        if tableRoot.linkControllable.validateLink(itemId: $0.itemId, entryId: nil) {
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
        let partialFolderIds: Set<UUID> = exportingFolder(results: &results)
        var allIds = itemIds
        allIds.ids[itemController.config.module] = Array(results)
        allIds.mergePartial(ids: Array(partialFolderIds), for: itemController.config.module)

        let newDiceIds = diceRoot.exportControllable.exporting(ids: diceIds)
        allIds.merge(other: newDiceIds)

        let newPdfIds = pdfRoot.exportControllable.exporting(ids: pdfIds)
        allIds.merge(other: newPdfIds)

        let newPhotoIds = photoRoot.exportControllable.exporting(ids: photoIds)
        allIds.merge(other: newPhotoIds)

        let newTableIds = tableRoot.exportControllable.exporting(ids: tableIds)
        allIds.merge(other: newTableIds)

        return allIds
    }
}
