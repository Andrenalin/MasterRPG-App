// @copyright André Trettin

import CoreRPG
import Foundation
import AudioRPG
import DiceRPG
import MapRPG
import PdfRPG
import WeatherRPG
import PhotoRPG
import RuleRPG
import SpaceRPG
import TableRPG
import CharacterRPG
import os.log

struct ExportController: Sendable {
    @MainActor init(rootManager: RootManager? = nil, root: AdventureRootModel, itemController: ItemController) {
        self.rootManager = rootManager
        self.root = root
        self.itemController = itemController
    }

    // Adventure is the hub itself, so its own hubControllable (for ExportControllable's
    // hub requirement) is just a lazy reference back to itself, not the whole RootManager.
    var rootManager: RootManager?
    let root: AdventureRootModel
    let itemController: ItemController

    private var resolvedRootManager: RootManager {
        guard let rootManager else {
            preconditionFailure("Adventure ExportController requires rootManager to be set before use.")
        }
        return rootManager
    }
}

extension ExportController: ExportControllable {
    var hubControllable: any RootExportControllable { root }
    var itemControllable: any ItemControllable { itemController }
    
    @MainActor public func exportingAll() -> ItemModuleIds {
        var itemIds = resolvedRootManager.audioRoot.exportControllable.exportingAll()
        itemIds.merge(other: resolvedRootManager.diceRoot.exportControllable.exportingAll())
        itemIds.merge(other: resolvedRootManager.mapRoot.exportControllable.exportingAll())
        itemIds.merge(other: resolvedRootManager.pdfRoot.exportControllable.exportingAll())
        itemIds.merge(other: resolvedRootManager.photoRoot.exportControllable.exportingAll())
        itemIds.merge(other: resolvedRootManager.ruleRoot.exportControllable.exportingAll())
        itemIds.merge(other: resolvedRootManager.spaceRoot.exportControllable.exportingAll())
        itemIds.merge(other: resolvedRootManager.tableRoot.exportControllable.exportingAll())
        itemIds.merge(other: resolvedRootManager.characterRoot.exportControllable.exportingAll())
        itemIds.merge(other: resolvedRootManager.weatherRoot.exportControllable.exportingAll())
        itemIds.merge(other: ItemModuleIds(dictionary: [itemController.config.module: itemController.itemDataModel.items.filter { itemController.itemSync(for: $0)?.displayState != 2 }]))
        return itemIds
    }
    
    @MainActor public func exporting(itemIds: ItemModuleIds) -> ItemModuleIds {
        var audioIds: Set<UUID> = []
        var diceIds: Set<UUID> = []
        var mapIds: Set<UUID> = []
        var pdfIds: Set<UUID> = []
        var photoIds: Set<UUID> = []
        var ruleIds: Set<UUID> = []
        var spaceIds: Set<UUID> = []
        var weatherIds: Set<UUID> = []
        var tableIds: Set<UUID> = []
        var valueIds: Set<UUID> = []

        let results = bfsExportResults(seedIds: itemIds.ids[itemController.config.module, default: []]) { id in
            guard let item = itemController.itemSync(for: id) else { return nil }

            if let photoId = item.photoId, resolvedRootManager.photoRoot.linkControllable.validateLink(itemId: photoId) {
                photoIds.insert(photoId)
            }

            if item.specialCategory {
                return item.entries.compactMap { entryId in
                    itemController.itemSync(for: entryId.childId) != nil ? entryId.childId : nil
                }
            }

            var childIds: [UUID] = []
            let links = item.entries.flatMap { $0.links(for: $0.content) }

            links.forEach {
                switch $0.module {
                case .adventure:
                    childIds.append($0.itemId)
                case .audio:
                    if resolvedRootManager.audioRoot.linkControllable.validateLink(itemId: $0.itemId) {
                        audioIds.insert($0.itemId)
                    }
                case .dice:
                    if resolvedRootManager.diceRoot.linkControllable.validateLink(itemId: $0.itemId) {
                        diceIds.insert($0.itemId)
                    }
                case .map:
                    if resolvedRootManager.mapRoot.linkControllable.validateLink(itemId: $0.itemId) {
                        mapIds.insert($0.itemId)
                    }
                case .pdf:
                    if resolvedRootManager.pdfRoot.linkControllable.validateLink(itemId: $0.itemId) {
                        pdfIds.insert($0.itemId)
                    }
                case .photo:
                    if resolvedRootManager.photoRoot.linkControllable.validateLink(itemId: $0.itemId) {
                        photoIds.insert($0.itemId)
                    }
                case .rule:
                    if resolvedRootManager.ruleRoot.linkControllable.validateLink(itemId: $0.itemId) {
                        ruleIds.insert($0.itemId)
                    }
                case .space:
                    if resolvedRootManager.spaceRoot.linkControllable.validateLink(itemId: $0.itemId) {
                        spaceIds.insert($0.itemId)
                    }
                case .table:
                    if resolvedRootManager.tableRoot.linkControllable.validateLink(itemId: $0.itemId) {
                        tableIds.insert($0.itemId)
                    }
                case .value:
                    if resolvedRootManager.characterRoot.linkControllable.validateLink(itemId: $0.itemId) {
                        valueIds.insert($0.itemId)
                    }
                case .weather:
                    if resolvedRootManager.weatherRoot.linkControllable.validateLink(itemId: $0.itemId) {
                        weatherIds.insert($0.itemId)
                    }
                default:
                    Logger.exportController.error("Table \(item.name, privacy: .private) export is not handling link \(String(describing: $0), privacy: .private)")
                }
            }
            return childIds
        }

        var allIds = finalizeExportResults(results, into: itemIds)
        let newAudioIds = resolvedRootManager.audioRoot.exportControllable.exporting(ids: audioIds)
        allIds.merge(other: newAudioIds)
        let newDiceIds = resolvedRootManager.diceRoot.exportControllable.exporting(ids: diceIds)
        allIds.merge(other: newDiceIds)
        let newMapIds = resolvedRootManager.mapRoot.exportControllable.exporting(ids: mapIds)
        allIds.merge(other: newMapIds)
        let newPdfIds = resolvedRootManager.pdfRoot.exportControllable.exporting(ids: pdfIds)
        allIds.merge(other: newPdfIds)
        let newPhotoIds = resolvedRootManager.photoRoot.exportControllable.exporting(ids: photoIds)
        allIds.merge(other: newPhotoIds)
        let newRuleIds = resolvedRootManager.ruleRoot.exportControllable.exporting(ids: ruleIds)
        allIds.merge(other: newRuleIds)
        let newSpaceIds = resolvedRootManager.spaceRoot.exportControllable.exporting(ids: spaceIds)
        allIds.merge(other: newSpaceIds)
        let newTableIds = resolvedRootManager.tableRoot.exportControllable.exporting(ids: tableIds)
        allIds.merge(other: newTableIds)
        let newValueIds = resolvedRootManager.characterRoot.exportControllable.exporting(ids: valueIds)
        allIds.merge(other: newValueIds)
        let newWeatherIds = resolvedRootManager.weatherRoot.exportControllable.exporting(ids: weatherIds)
        allIds.merge(other: newWeatherIds)
        return allIds
    }
    
    public func additionalExport(itemIds: ItemModuleIds, stream outputStream: OutputStream, exportModel: ItemDataExportModel) async throws -> ItemModuleIds {
        let ids1 = try await resolvedRootManager.audioRoot.exportControllable.export(itemIds: itemIds, into: outputStream, exportModel: exportModel)
        let ids2 = try await resolvedRootManager.diceRoot.exportControllable.export(itemIds: ids1, into: outputStream, exportModel: exportModel)
        let ids3 = try await resolvedRootManager.mapRoot.exportControllable.export(itemIds: ids2, into: outputStream, exportModel: exportModel)
        let ids4 = try await resolvedRootManager.pdfRoot.exportControllable.export(itemIds: ids3, into: outputStream, exportModel: exportModel)
        let ids5 = try await resolvedRootManager.photoRoot.exportControllable.export(itemIds: ids4, into: outputStream, exportModel: exportModel)
        let ids6 = try await resolvedRootManager.spaceRoot.exportControllable.export(itemIds: ids5, into: outputStream, exportModel: exportModel)
        let ids7 = try await resolvedRootManager.tableRoot.exportControllable.export(itemIds: ids6, into: outputStream, exportModel: exportModel)
        let ids8 = try await resolvedRootManager.characterRoot.exportControllable.export(itemIds: ids7, into: outputStream, exportModel: exportModel)
        let ids9 = try await resolvedRootManager.weatherRoot.exportControllable.export(itemIds: ids8, into: outputStream, exportModel: exportModel)
        return ids9
    }

    public func finalExport(itemIds: ItemModuleIds, stream outputStream: OutputStream, exportModel: ItemDataExportModel) async throws -> ItemModuleIds {
        try await resolvedRootManager.ruleRoot.exportControllable.export(
            itemIds: itemIds,
            into: outputStream,
            exportModel: exportModel
        )
    }
}
