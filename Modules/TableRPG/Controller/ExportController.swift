// @copyright André Trettin

import CoreRPG
import Foundation
import os.log
import DiceRPG
import PdfRPG

struct ExportController: Sendable {
    @MainActor init(diceRoot: DiceRootModel, pdfRoot: PdfRootModel, itemController: ItemController) {
        self.diceRoot = diceRoot
        self.pdfRoot = pdfRoot
        self.itemController = itemController
        self.exportModel = ExportModel()
    }

    let exportModel: ExportModel
    let diceRoot: DiceRootModel
    let pdfRoot: PdfRootModel
    let itemController: ItemController
}

extension ExportController: ExportModelBacked {
    var itemControllable: any ItemControllable { itemController }

    public func exportingAll() -> ItemModuleIds {
        var allIds = diceRoot.exportControllable.exportingAll()
        allIds.merge(other: pdfRoot.exportControllable.exportingAll())
        allIds.merge(other: ItemModuleIds(dictionary: [itemController.config.module: itemController.itemDataModel.items.filter { itemController.itemSync(for: $0)?.displayState != DisplayStateMask.totalHidden.rawValue }]))

        return allIds
    }
    
    @MainActor public func exporting(itemIds: ItemModuleIds) -> ItemModuleIds {
        var diceIds: Set<UUID> = []
        var pdfIds: Set<UUID> = []

        let results = bfsExportResults(seedIds: itemIds.ids[itemController.config.module, default: []]) { id in
            guard let item = itemController.itemSync(for: id) else { return nil }

            if let diceId = item.diceId, diceRoot.linkControllable.validateLink(itemId: diceId) {
                diceIds.insert(diceId)
            }

            if item.specialCategory {
                return item.entries.compactMap { entryId in
                    itemController.itemSync(for: entryId.childId) != nil ? entryId.childId : nil
                }
            }

            var childIds: [UUID] = []
            let links = item.entries.flatMap { entry in
                entry.links(for: entry.content)
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
                case .table:
                    if itemController.itemSync(for: $0.itemId) != nil {
                        childIds.append($0.itemId)
                    }
                default:
                    Logger.exportController.error("Table \(item.name, privacy: .private) export is not handling link \($0.markDown, privacy: .private)")
                }
            }
            return childIds
        }

        var allIds = finalizeExportResults(results, into: itemIds)
        let newDiceIds = diceRoot.exportControllable.exporting(ids: diceIds)
        allIds.merge(other: newDiceIds)
        let newPdfIds = pdfRoot.exportControllable.exporting(ids: pdfIds)
        allIds.merge(other: newPdfIds)
        return allIds
    }
}
