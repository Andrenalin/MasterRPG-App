// @copyright André Trettin

import CoreRPG
import Foundation
import AudioRPG
import DiceRPG
import PdfRPG
import PhotoRPG
import TableRPG
import CharacterRPG
import os.log

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
    let root: MapRootModel
    let audioRoot: AudioRootModel
    let diceRoot: DiceRootModel
    let pdfRoot: PdfRootModel
    let photoRoot: PhotoRootModel
    let tableRoot: TableRootModel
    let characterRoot: CharacterRootModel
    let itemController: ItemController
}

extension ExportController: ExportModelBacked {
    var itemControllable: any ItemControllable { itemController }

    public func exportingAll() -> ItemModuleIds {
        var itemIds = ItemModuleIds(dictionary: [itemController.config.module: itemController.itemDataModel.items.filter { itemController.itemSync(for: $0)?.displayState != DisplayStateMask.totalHidden.rawValue }])

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
        var audioIds: Set<UUID> = []
        var diceIds: Set<UUID> = []
        var pdfIds: Set<UUID> = []
        var photoIds: Set<UUID> = []
        var tableIds: Set<UUID> = []
        var valueIds: Set<UUID> = []
        let isGameMode = itemControllable.itemDataModel.isGameMode

        let results = bfsExportResults(seedIds: itemIds.ids[itemController.config.module, default: []]) { id in
            guard let item = itemController.itemSync(for: id) else { return nil }

            photoIds.formUnion(item.mapPins.compactMap { $0.photoId }.compactMap { photoRoot.linkControllable.validateLink(itemId: $0) ? $0 : nil })
            if !isGameMode {
                valueIds.formUnion(item.mapPins.compactMap { $0.characterId }.compactMap { characterRoot.linkControllable.validateLink(itemId: $0) ? $0 : nil })
            }
            if let photoId = item.photoId, photoRoot.linkControllable.validateLink(itemId: photoId) {
                photoIds.insert(photoId)
            }

            if item.specialCategory {
                return item.entries.compactMap { entryId in
                    itemController.itemSync(for: entryId.childId) != nil ? entryId.childId : nil
                }
            }

            var childIds: [UUID] = []
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
                    if root.linkControllable.validateLink(itemId: $0.itemId) {
                        childIds.append($0.itemId)
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
                    if tableRoot.linkControllable.validateLink(itemId: $0.itemId) {
                        tableIds.insert($0.itemId)
                    }
                case .value:
                    if !isGameMode, characterRoot.linkControllable.validateLink(itemId: $0.itemId) {
                        valueIds.insert($0.itemId)
                    }
                default:
                    Logger.exportController.error("Table \(item.name, privacy: .private) export is not handling link \(String(describing: $0), privacy: .private)")
                }
            }
            return childIds
        }
        // In a running game the map package must carry the player photos as
        // well — player pins may not be appended to the exported item's mapPins
        // yet. Only when a map is actually exported: the hub chain also calls
        // this with no map ids at all.
        if itemControllable.itemDataModel.isGameMode, !results.isEmpty {
            photoIds.formUnion(root.gameController.mapGameModel.playerPins.compactMap { pin in
                guard let photoId = pin.photoId, photoRoot.linkControllable.validateLink(itemId: photoId) else { return nil }
                return photoId
            })
        }

        var allIds = finalizeExportResults(results, into: itemIds)
        let newAudioIds = audioRoot.exportControllable.exporting(ids: audioIds)
        allIds.merge(other: newAudioIds)
        let newDiceIds = diceRoot.exportControllable.exporting(ids: diceIds)
        allIds.merge(other: newDiceIds)
        let newPdfIds = pdfRoot.exportControllable.exporting(ids: pdfIds)
        allIds.merge(other: newPdfIds)
        let newPhotoIds = photoRoot.exportControllable.exporting(ids: photoIds)
        allIds.merge(other: newPhotoIds)
        let newTableIds = tableRoot.exportControllable.exporting(ids: tableIds)
        allIds.merge(other: newTableIds)
        let newValueIds = characterRoot.exportControllable.exporting(ids: valueIds)
        allIds.merge(other: newValueIds)
        return allIds
    }
}
