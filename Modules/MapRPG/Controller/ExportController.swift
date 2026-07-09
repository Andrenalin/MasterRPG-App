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
    @MainActor init(root: MapRootModel, audioRoot: AudioRootModel, diceRoot: DiceRootModel, pdfRoot: PdfRootModel, photoRoot: PhotoRootModel, tableRoot: TableRootModel, characterRoot: CharacterRootModel, itemController: ItemController) {
        self.root = root
        self.audioRoot = audioRoot
        self.diceRoot = diceRoot
        self.pdfRoot = pdfRoot
        self.photoRoot = photoRoot
        self.tableRoot = tableRoot
        self.characterRoot = characterRoot
        self.itemController = itemController
        self.exportModel = ExportModel()
    }

    let exportModel: ExportModel
    var hubControllable: any RootExportControllable {
        get { exportModel.hubControllable! }
        set { exportModel.hubControllable = newValue }
    }
    let root: MapRootModel
    let audioRoot: AudioRootModel
    let diceRoot: DiceRootModel
    let pdfRoot: PdfRootModel
    let photoRoot: PhotoRootModel
    let tableRoot: TableRootModel
    let characterRoot: CharacterRootModel
    let itemController: ItemController
}

extension ExportController: ExportControllable {
    var itemControllable: any ItemControllable { itemController }

    public func exportingAll() -> ItemModuleIds {
        var itemIds = ItemModuleIds(dictionary: [itemController.config.module: itemController.itemDataModel.items.filter { itemController.itemSync(for: $0)?.displayState != 2 }])

        if !itemControllable.itemDataModel.isGameMode {
            itemIds.merge(other: audioRoot.exportControllable.exportingAll())
            itemIds.merge(other: diceRoot.exportControllable.exportingAll())
            itemIds.merge(other: pdfRoot.exportControllable.exportingAll())
            itemIds.merge(other: photoRoot.exportControllable.exportingAll())
            itemIds.merge(other: tableRoot.exportControllable.exportingAll())
            itemIds.merge(other: characterRoot.exportControllable.exportingAll())
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

            photoIds.formUnion(item.mapPins.compactMap { $0.photoId }.compactMap { photoRoot.linkControllable.validateLink(itemId: $0) ? $0 : nil })
            if let photoId = item.photoId, photoRoot.linkControllable.validateLink(itemId: photoId) {
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
                        if audioRoot.linkControllable.validateLink(itemId: $0.itemId) {
                            audioIds.insert($0.itemId)
                        }
                    case .dice:
                        if diceRoot.linkControllable.validateLink(itemId: $0.itemId) {
                            diceIds.insert($0.itemId)
                        }
                    case .map:
                        if !(results.contains($0.itemId) || checkIds.contains($0.itemId)) && root.linkControllable.validateLink(itemId: $0.itemId) {
                            checkIds.append($0.itemId)
                        }
                    case .photo:
                        if photoRoot.linkControllable.validateLink(itemId: $0.itemId) {
                            photoIds.insert($0.itemId)
                        }
                    case .table:
                        if tableRoot.linkControllable.validateLink(itemId: $0.itemId) {
                            tableIds.insert($0.itemId)
                        }
                    case .value:
                        if characterRoot.linkControllable.validateLink(itemId: $0.itemId) {
                            valueIds.insert($0.itemId)
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
        let newAudioIds = audioRoot.exportControllable.exporting(ids: audioIds)
        allIds.merge(other: newAudioIds)
        let newDiceIds = diceRoot.exportControllable.exporting(ids: diceIds)
        allIds.merge(other: newDiceIds)
        let newPhotoIds = photoRoot.exportControllable.exporting(ids: photoIds)
        allIds.merge(other: newPhotoIds)
        let newTableIds = tableRoot.exportControllable.exporting(ids: tableIds)
        allIds.merge(other: newTableIds)
        let newValueIds = characterRoot.exportControllable.exporting(ids: valueIds)
        allIds.merge(other: newValueIds)
        return allIds
    }
}
