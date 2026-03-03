// @copyright André Trettin

import CoreRPG
import Foundation
import AudioRPG
import DiceRPG
import PdfRPG
import PhotoRPG
import TableRPG
import CharacterRPG

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
        var itemIds = ItemModuleIds(dictionary: [itemController.config.module: itemController.itemDataModel.items.map { $0 }])

        if !itemControllable.itemDataModel.isGameMode {
            itemIds.merge(other: rootManager.audioRoot.exportControllable.exportingAll())
            itemIds.merge(other: rootManager.diceRoot.exportControllable.exportingAll())
            itemIds.merge(other: rootManager.pdfRoot.exportControllable.exportingAll())
            itemIds.merge(other: rootManager.photoRoot.exportControllable.exportingAll())
            itemIds.merge(other: rootManager.tableRoot.exportControllable.exportingAll())
            itemIds.merge(other: rootManager.characterRoot.exportControllable.exportingAll())
        }
        return itemIds
    }
    
    @MainActor public func exporting(itemIds: ItemModuleIds) -> ItemModuleIds {
        var checkIds = itemIds.ids[itemController.config.module, default: []]
        var results: Set<UUID> = []
        var audioIds: Set<UUID> = []
        var diceIds: Set<UUID> = []
        var photoIds: Set<UUID> = []
        var tableIds: Set<UUID> = []
        var valueIds: Set<UUID> = []

        while !checkIds.isEmpty {
            let id = checkIds.removeLast()
            guard let item = itemController.itemSync(for: id) else {
                Task {
                    await logExport(title: "exporting not found \(id.uuidString))", count: 1)
                }
                continue
            }
            results.insert(id)

            photoIds.formUnion(item.mapPins.compactMap { $0.photoId }.compactMap { rootManager.photoRoot.linkControllable.validateLink(itemId: $0) ? $0 : nil })
            if let photoId = item.photoId, rootManager.photoRoot.linkControllable.validateLink(itemId: photoId) {
                photoIds.insert(photoId)
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
                
                let links = item.entries.flatMap {
                    let text = $0.content
                    return LinkReplaceController.links(for: text)
                }
                
                links.forEach {
                    switch $0.module {
                    case .audio:
                        if rootManager.audioRoot.linkControllable.validateLink(itemId: $0.itemId) {
                            audioIds.insert($0.itemId)
                        }
                    case .dice:
                        if rootManager.diceRoot.linkControllable.validateLink(itemId: $0.itemId) {
                            diceIds.insert($0.itemId)
                        }
                    case .map:
                        if !(results.contains($0.itemId) || checkIds.contains($0.itemId)) && rootManager.mapRoot.linkControllable.validateLink(itemId: $0.itemId) {
                            checkIds.append($0.itemId)
                        }
                    case .photo:
                        if rootManager.photoRoot.linkControllable.validateLink(itemId: $0.itemId) {
                            photoIds.insert($0.itemId)
                        }
                    case .table:
                        if rootManager.tableRoot.linkControllable.validateLink(itemId: $0.itemId) {
                            tableIds.insert($0.itemId)
                        }
                    case .value:
                        if rootManager.characterRoot.linkControllable.validateLink(itemId: $0.itemId) {
                            valueIds.insert($0.itemId)
                        }
                    default:
                        print("*** ERROR table \(item.name) export is not handling link \($0)")
                    }
                }
            }
        }
        var allIds = itemIds
        allIds.ids[itemController.config.module] = Array(results)
        let newAudioIds = rootManager.audioRoot.exportControllable.exporting(ids: audioIds)
        allIds.merge(other: newAudioIds)
        let newDiceIds = rootManager.diceRoot.exportControllable.exporting(ids: diceIds)
        allIds.merge(other: newDiceIds)
        let newPhotoIds = rootManager.photoRoot.exportControllable.exporting(ids: photoIds)
        allIds.merge(other: newPhotoIds)
        let newTableIds = rootManager.tableRoot.exportControllable.exporting(ids: tableIds)
        allIds.merge(other: newTableIds)
        let newValueIds = rootManager.characterRoot.exportControllable.exporting(ids: valueIds)
        allIds.merge(other: newValueIds)
        return allIds
    }
}
