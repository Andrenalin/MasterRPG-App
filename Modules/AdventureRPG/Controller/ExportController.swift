// @copyright André Trettin

import CoreRPG
import Foundation
import AudioRPG
import DiceRPG
import MapRPG
import PdfRPG
import WeatherRPG
import PhotoRPG
import SpaceRPG
import TableRPG
import CharacterRPG

struct ExportController: Sendable {
    @MainActor init(rootManager: RootManager, root: AdventureRootModel, itemController: ItemController) {
        self.rootManager = rootManager
        self.root = root
        self.itemController = itemController
    }

    // Adventure is the hub itself, so its own rootController (for ExportControllable's
    // hub requirement) is just a lazy reference back to itself, not the whole RootManager.
    let rootManager: RootManager
    let root: AdventureRootModel
    let itemController: ItemController
}

extension ExportController: ExportControllable {
    var rootController: any RootControllable { root }
    var itemControllable: any ItemControllable { itemController }
    
    @MainActor public func exportingAll() -> ItemModuleIds {
        var itemIds = rootManager.audioRoot.exportControllable.exportingAll()
        itemIds.merge(other: rootManager.diceRoot.exportControllable.exportingAll())
        itemIds.merge(other: rootManager.mapRoot.exportControllable.exportingAll())
        itemIds.merge(other: rootManager.pdfRoot.exportControllable.exportingAll())
        itemIds.merge(other: rootManager.photoRoot.exportControllable.exportingAll())
        itemIds.merge(other: rootManager.spaceRoot.exportControllable.exportingAll())
        itemIds.merge(other: rootManager.tableRoot.exportControllable.exportingAll())
        itemIds.merge(other: rootManager.characterRoot.exportControllable.exportingAll())
        itemIds.merge(other: rootManager.weatherRoot.exportControllable.exportingAll())
        itemIds.merge(other: ItemModuleIds(dictionary: [itemController.config.module: itemController.itemDataModel.items.filter { itemController.itemSync(for: $0)?.displayState != 2 }]))
        return itemIds
    }
    
    @MainActor public func exporting(itemIds: ItemModuleIds) -> ItemModuleIds {
        var checkIds = itemIds.ids[itemController.config.module, default: []]
        var results: Set<UUID> = []
        var audioIds: Set<UUID> = []
        var diceIds: Set<UUID> = []
        var mapIds: Set<UUID> = []
        var pdfIds: Set<UUID> = []
        var photoIds: Set<UUID> = []
        var spaceIds: Set<UUID> = []
        var weatherIds: Set<UUID> = []
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
                
                let links = item.entries.flatMap { $0.links(for: $0.content) }
                
                links.forEach {
                    switch $0.module {
                    case .adventure:
                        if !(results.contains($0.itemId) || checkIds.contains($0.itemId)) {
                            checkIds.append($0.itemId)
                        }
                    case .audio:
                        if rootManager.audioRoot.linkControllable.validateLink(itemId: $0.itemId) {
                            audioIds.insert($0.itemId)
                        }
                    case .dice:
                        if rootManager.diceRoot.linkControllable.validateLink(itemId: $0.itemId) {
                            diceIds.insert($0.itemId)
                        }
                    case .map:
                        if rootManager.mapRoot.linkControllable.validateLink(itemId: $0.itemId) {
                            mapIds.insert($0.itemId)
                        }
                    case .pdf:
                        if rootManager.pdfRoot.linkControllable.validateLink(itemId: $0.itemId) {
                            pdfIds.insert($0.itemId)
                        }
                    case .photo:
                        if rootManager.photoRoot.linkControllable.validateLink(itemId: $0.itemId) {
                            photoIds.insert($0.itemId)
                        }
                    case .space:
                        if rootManager.spaceRoot.linkControllable.validateLink(itemId: $0.itemId) {
                            spaceIds.insert($0.itemId)
                        }
                    case .table:
                        if rootManager.tableRoot.linkControllable.validateLink(itemId: $0.itemId) {
                            tableIds.insert($0.itemId)
                        }
                    case .value:
                        if rootManager.characterRoot.linkControllable.validateLink(itemId: $0.itemId) {
                            valueIds.insert($0.itemId)
                        }
                    case .weather:
                        if rootManager.weatherRoot.linkControllable.validateLink(itemId: $0.itemId) {
                            weatherIds.insert($0.itemId)
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
        let newAudioIds = rootManager.audioRoot.exportControllable.exporting(ids: audioIds)
        allIds.merge(other: newAudioIds)
        let newDiceIds = rootManager.diceRoot.exportControllable.exporting(ids: diceIds)
        allIds.merge(other: newDiceIds)
        let newMapIds = rootManager.mapRoot.exportControllable.exporting(ids: mapIds)
        allIds.merge(other: newMapIds)
        let newPdfIds = rootManager.pdfRoot.exportControllable.exporting(ids: pdfIds)
        allIds.merge(other: newPdfIds)
        let newPhotoIds = rootManager.photoRoot.exportControllable.exporting(ids: photoIds)
        allIds.merge(other: newPhotoIds)
        let newSpaceIds = rootManager.spaceRoot.exportControllable.exporting(ids: spaceIds)
        allIds.merge(other: newSpaceIds)
        let newTableIds = rootManager.tableRoot.exportControllable.exporting(ids: tableIds)
        allIds.merge(other: newTableIds)
        let newValueIds = rootManager.characterRoot.exportControllable.exporting(ids: valueIds)
        allIds.merge(other: newValueIds)
        let newWeatherIds = rootManager.weatherRoot.exportControllable.exporting(ids: weatherIds)
        allIds.merge(other: newWeatherIds)
        return allIds
    }
    
    public func additionalExport(itemIds: ItemModuleIds, stream outputStream: OutputStream, exportModel: ItemDataExportModel) async throws -> ItemModuleIds {
        let ids1 = try await rootManager.audioRoot.exportControllable.export(itemIds: itemIds, into: outputStream, exportModel: exportModel)
        let ids2 = try await rootManager.diceRoot.exportControllable.export(itemIds: ids1, into: outputStream, exportModel: exportModel)
        let ids3 = try await rootManager.mapRoot.exportControllable.export(itemIds: ids2, into: outputStream, exportModel: exportModel)
        let ids4 = try await rootManager.pdfRoot.exportControllable.export(itemIds: ids3, into: outputStream, exportModel: exportModel)
        let ids5 = try await rootManager.photoRoot.exportControllable.export(itemIds: ids4, into: outputStream, exportModel: exportModel)
        let ids6 = try await rootManager.spaceRoot.exportControllable.export(itemIds: ids5, into: outputStream, exportModel: exportModel)
        let ids7 = try await rootManager.tableRoot.exportControllable.export(itemIds: ids6, into: outputStream, exportModel: exportModel)
        let ids8 = try await rootManager.characterRoot.exportControllable.export(itemIds: ids7, into: outputStream, exportModel: exportModel)
        let ids9 = try await rootManager.weatherRoot.exportControllable.export(itemIds: ids8, into: outputStream, exportModel: exportModel)
        return ids9
    }
}
