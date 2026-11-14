// @copyright André Trettin

import CoreRPG
import Foundation
import PdfRPG
import TableRPG
import PhotoRPG
import DiceRPG
import os.log

struct ExportController: Sendable {
    // `hubControllable` reaches Adventure's hub exporter (ExportControllable.hubControllable).
    // Every other export path below uses the narrow diceRoot/pdfRoot/photoRoot/tableRoot refs instead.
    @MainActor init(diceRoot: DiceRootModel, pdfRoot: PdfRootModel, photoRoot: PhotoRootModel, tableRoot: TableRootModel, itemController: ItemController) {
        self.diceRoot = diceRoot
        self.pdfRoot = pdfRoot
        self.photoRoot = photoRoot
        self.tableRoot = tableRoot
        self.itemController = itemController
        self.exportModel = ExportModel()
    }

    let exportModel: ExportModel
    let diceRoot: DiceRootModel
    let pdfRoot: PdfRootModel
    let photoRoot: PhotoRootModel
    let tableRoot: TableRootModel
    let itemController: ItemController
}

extension ExportController: ExportModelBacked {
    var itemControllable: any ItemControllable { itemController }

    public func exportingAll() -> ItemModuleIds {
        var allIds = photoRoot.exportControllable.exportingAll()
        allIds.merge(other: tableRoot.exportControllable.exportingAll())
        allIds.merge(other: ItemModuleIds(dictionary: [itemController.config.module: itemController.itemDataModel.items.filter { itemController.itemSync(for: $0)?.isHidden != true }]))
        return allIds
    }
    
    @MainActor public func exporting(itemIds: ItemModuleIds) -> ItemModuleIds {
        var diceIds: Set<UUID> = []
        var photoIds: Set<UUID> = []
        var pdfIds: Set<UUID> = []
        var tableIds: Set<UUID> = []

        let results = bfsExportResults(seedIds: itemIds.ids[itemController.config.module, default: []]) { id in
            guard let item = itemController.itemSync(for: id) else { return nil }

            if let diceId = item.diceId, diceRoot.linkControllable.validateLink(itemId: diceId) {
                diceIds.insert(diceId)
            }

            if let photoId = item.photoId, photoRoot.linkControllable.validateLink(itemId: photoId) {
                photoIds.insert(photoId)
            }
            photoIds.formUnion(item.photos.filter { photoRoot.linkControllable.validateLink(itemId: $0) })

            if item.specialCategory {
                return item.entries.compactMap { entryId in
                    itemController.itemSync(for: entryId.childId) != nil ? entryId.childId : nil
                }
            }

            var childIds: [UUID] = []
            var links: [LinkReplaceModel] = []
            item.entries.forEach { entry in
                links.append(contentsOf: LinkReplaceController.links(for: entry.name))
                links.append(contentsOf: LinkReplaceController.links(for: entry.value))
                if let valueId = entry.valueId {
                    childIds.append(valueId)
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
                    if itemController.itemSync(for: $0.itemId) != nil {
                        childIds.append($0.itemId)
                    }
                default:
                    Logger.exportController.error("Value \(item.name, privacy: .private) export is not handling link \(String(describing: $0), privacy: .private)")
                }
            }
            return childIds
        }

        var allIds = finalizeExportResults(results, into: itemIds)

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
