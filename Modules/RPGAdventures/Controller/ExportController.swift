// @copyright André Trettin

import AndrenalinKit
import Foundation
import RPGAudios
import RPGDie
import RPGMaps
import RPGPdfs
import RPGWeathers
import RPGPhotos
import RPGSpaces
import RPGTables
import RPGValues

struct ExportController: Sendable {
    @MainActor
    init(root: AdventureRootModel, itemController: ItemController, gameExporter: Bool) {
        self.root = root
        self.itemController = itemController
        self.exportModel = ItemDataExportModel(gameExporter: gameExporter)
    }

    weak var root: AdventureRootModel!
    let itemController: ItemController

    public let exportModel: ItemDataExportModel
}

extension ExportController: ExportControllable {
    var itemControllable: any ItemControllable {
        itemController as (any ItemControllable)
    }

    public func exportingAll() -> ItemModuleIds {
        var itemIds = root.audioRoot.exportControllable.exportingAll()
        itemIds.merge(other: root.diceRoot.exportControllable.exportingAll())
        itemIds.merge(other: root.mapRoot.exportControllable.exportingAll())
        itemIds.merge(other: root.pdfRoot.exportControllable.exportingAll())
        itemIds.merge(other: root.photoRoot.exportControllable.exportingAll())
        itemIds.merge(other: root.spaceRoot.exportControllable.exportingAll())
        itemIds.merge(other: root.tableRoot.exportControllable.exportingAll())
        itemIds.merge(other: root.valueRoot.exportControllable.exportingAll())
        itemIds.merge(other: root.weatherRoot.exportControllable.exportingAll())
        itemIds.merge(other: ItemModuleIds(dictionary: [itemController.itemDataModel.networkModule: itemController.itemDataModel.items.map { $0 }]))
        return itemIds
    }
    
    public func exporting(itemIds: ItemModuleIds) -> ItemModuleIds {
        var checkIds = itemIds.ids[itemController.itemDataModel.networkModule, default: []]
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

            if let photoId = item.photoId, root.photoRoot.linkController.validateLink(itemId: photoId) {
                photoIds.insert(photoId)
            }

            let links = item.entries.flatMap { $0.links(for: $0.content) }

            links.forEach {
                switch $0.module {
                case .adventure:
                    if !(results.contains($0.itemId) || checkIds.contains($0.itemId)) {
                        checkIds.append($0.itemId)
                    }
                case .audio:
                    if root.audioRoot.linkController.validateLink(itemId: $0.itemId) {
                        audioIds.insert($0.itemId)
                    }
                case .dice:
                    if root.diceRoot.linkController.validateLink(itemId: $0.itemId) {
                        diceIds.insert($0.itemId)
                    }
                case .map:
                    if root.mapRoot.linkController.validateLink(itemId: $0.itemId) {
                        mapIds.insert($0.itemId)
                    }
                case .pdf:
                    if root.pdfRoot.linkController.validateLink(itemId: $0.itemId) {
                        pdfIds.insert($0.itemId)
                    }
                case .photo:
                    if root.photoRoot.linkController.validateLink(itemId: $0.itemId) {
                        photoIds.insert($0.itemId)
                    }
                case .space:
                    if root.spaceRoot.linkController.validateLink(itemId: $0.itemId) {
                        spaceIds.insert($0.itemId)
                    }
                case .table:
                    if root.tableRoot.linkController.validateLink(itemId: $0.itemId) {
                        tableIds.insert($0.itemId)
                    }
                case .value:
                    if root.valueRoot.linkController.validateLink(itemId: $0.itemId) {
                        valueIds.insert($0.itemId)
                    }
                case .weather:
                    if root.weatherRoot.linkController.validateLink(itemId: $0.itemId) {
                        weatherIds.insert($0.itemId)
                    }
                default:
                    print("*** ERROR table \(item.name) export is not handling link \($0)")
                }
            }
        }        
        var allIds = itemIds
        allIds.ids[itemController.itemDataModel.networkModule] = Array(results)
        let newAudioIds = exportModel.gameExporter ? root.audioRoot.gameControllable.exportControllable.exporting(ids: audioIds) : root.audioRoot.exportControllable.exporting(ids: audioIds)
        allIds.merge(other: newAudioIds)
        let newDiceIds = exportModel.gameExporter ? root.diceRoot.gameControllable.exportControllable.exporting(ids: diceIds) : root.diceRoot.exportControllable.exporting(ids: diceIds)
        allIds.merge(other: newDiceIds)
        let newMapIds = exportModel.gameExporter ? root.mapRoot.gameControllable.exportControllable.exporting(ids: mapIds) : root.mapRoot.exportControllable.exporting(ids: mapIds)
        allIds.merge(other: newMapIds)
        let newPdfIds = exportModel.gameExporter ? root.pdfRoot.gameControllable.exportControllable.exporting(ids: pdfIds) :  root.pdfRoot.exportControllable.exporting(ids: pdfIds)
        allIds.merge(other: newPdfIds)
        let newPhotoIds = exportModel.gameExporter ? root.photoRoot.gameControllable.exportControllable.exporting(ids: photoIds) : root.photoRoot.exportControllable.exporting(ids: photoIds)
        allIds.merge(other: newPhotoIds)
        let newSpaceIds = exportModel.gameExporter ? root.spaceRoot.gameControllable.exportControllable.exporting(ids: spaceIds) : root.spaceRoot.exportControllable.exporting(ids: spaceIds)
        allIds.merge(other: newSpaceIds)
        let newTableIds = exportModel.gameExporter ? root.tableRoot.gameControllable.exportControllable.exporting(ids: tableIds) : root.tableRoot.exportControllable.exporting(ids: tableIds)
        allIds.merge(other: newTableIds)
        let newValueIds = exportModel.gameExporter ? root.valueRoot.gameControllable.exportControllable.exporting(ids: valueIds) : root.valueRoot.exportControllable.exporting(ids: valueIds)
        allIds.merge(other: newValueIds)
        let newWeatherIds = exportModel.gameExporter ? root.weatherRoot.gameControllable.exportControllable.exporting(ids: weatherIds) : root.weatherRoot.exportControllable.exporting(ids: weatherIds)
        allIds.merge(other: newWeatherIds)
        return allIds
    }
    
    public func additionalExport(itemIds: ItemModuleIds, stream outputStream: OutputStream, counterUpdater: @MainActor @Sendable (Int?, Bool) async -> Void) async throws -> ItemModuleIds {

        if await exportModel.gameExporter {
            let ids1 = try await root.audioRoot.gameControllable.exportControllable.export(itemIds: itemIds, into: outputStream, counterUpdater: counterUpdater)
            let ids2 = try await root.diceRoot.gameControllable.exportControllable.export(itemIds: ids1, into: outputStream, counterUpdater: counterUpdater)
            let ids3 = try await root.mapRoot.gameControllable.exportControllable.export(itemIds: ids2, into: outputStream, counterUpdater: counterUpdater)
            let ids4 = try await root.pdfRoot.gameControllable.exportControllable.export(itemIds: ids3, into: outputStream, counterUpdater: counterUpdater)
            let ids5 = try await root.photoRoot.gameControllable.exportControllable.export(itemIds: ids4, into: outputStream, counterUpdater: counterUpdater)
            let ids6 = try await root.spaceRoot.gameControllable.exportControllable.export(itemIds: ids5, into: outputStream, counterUpdater: counterUpdater)
            let ids7 = try await root.tableRoot.gameControllable.exportControllable.export(itemIds: ids6, into: outputStream, counterUpdater: counterUpdater)
            let ids8 = try await root.valueRoot.gameControllable.exportControllable.export(itemIds: ids7, into: outputStream, counterUpdater: counterUpdater)
            let ids9 = try await root.weatherRoot.gameControllable.exportControllable.export(itemIds: ids8, into: outputStream, counterUpdater: counterUpdater)
            return ids9
        } else {
            let ids1 = try await root.audioRoot.exportControllable.export(itemIds: itemIds, into: outputStream, counterUpdater: counterUpdater)
            let ids2 = try await root.diceRoot.exportControllable.export(itemIds: ids1, into: outputStream, counterUpdater: counterUpdater)
            let ids3 = try await root.mapRoot.exportControllable.export(itemIds: ids2, into: outputStream, counterUpdater: counterUpdater)
            let ids4 = try await root.pdfRoot.exportControllable.export(itemIds: ids3, into: outputStream, counterUpdater: counterUpdater)
            let ids5 = try await root.photoRoot.exportControllable.export(itemIds: ids4, into: outputStream, counterUpdater: counterUpdater)
            let ids6 = try await root.spaceRoot.exportControllable.export(itemIds: ids5, into: outputStream, counterUpdater: counterUpdater)
            let ids7 = try await root.tableRoot.exportControllable.export(itemIds: ids6, into: outputStream, counterUpdater: counterUpdater)
            let ids8 = try await root.valueRoot.exportControllable.export(itemIds: ids7, into: outputStream, counterUpdater: counterUpdater)
            let ids9 = try await root.weatherRoot.exportControllable.export(itemIds: ids8, into: outputStream, counterUpdater: counterUpdater)
            return ids9
        }
    }
}
