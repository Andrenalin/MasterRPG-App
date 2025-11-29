// @copyright André Trettin

import CoreRPG
import Foundation
import TableRPG
import PhotoRPG
import DiceRPG

struct ExportController: Sendable {
    @MainActor
    init(diceRoot: DiceRootModel, photoRoot: PhotoRootModel, tableRoot: TableRootModel, itemController: ItemController, gameExporter: Bool) {
        self.diceRoot = diceRoot
        self.photoRoot = photoRoot
        self.tableRoot = tableRoot
        
        self.itemController = itemController
        self.exportModel = ItemDataExportModel(gameExporter: gameExporter)
    }

    let diceRoot: DiceRootModel
    let photoRoot: PhotoRootModel
    let tableRoot: TableRootModel
    
    let itemController: ItemController

    public let exportModel: ItemDataExportModel
}

extension ExportController: ExportControllable {
    var itemControllable: any ItemControllable {
        itemController
    }

    public func exportingAll() -> ItemModuleIds {
        var allIds = photoRoot.exportControllable.exportingAll()
        allIds.merge(other: tableRoot.exportControllable.exportingAll())
        allIds.merge(other: ItemModuleIds(dictionary: [itemController.itemDataModel.networkModule: itemController.itemDataModel.items.map { $0 }]))
        return allIds
    }
    
    public func exporting(itemIds: ItemModuleIds) -> ItemModuleIds {
        var checkIds = itemIds.ids[itemController.itemDataModel.networkModule, default: []]
        var results: Set<UUID> = []
        var diceIds: Set<UUID> = []
        var photoIds: Set<UUID> = []
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

            if let photoId = item.photoId, photoRoot.linkController.validateLink(itemId: photoId) {
                photoIds.insert(photoId)
            }
            photoIds.formUnion(item.photos.filter { photoRoot.linkController.validateLink(itemId: $0) })

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
                    if diceRoot.linkController.validateLink(itemId: $0.itemId) {
                        diceIds.insert($0.itemId)
                    }
                case .photo:
                    if photoRoot.linkController.validateLink(itemId: $0.itemId) {
                        photoIds.insert($0.itemId)
                    }
                case .table:
                    if tableRoot.linkController.validateLink(itemId: $0.itemId, entryId: nil) {
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
        var allIds = itemIds
        allIds.ids[itemController.itemDataModel.networkModule] = Array(results)

        let newDiceIds = diceRoot.exportControllable.exporting(ids: diceIds)
        allIds.merge(other: newDiceIds)

        let newPhotoIds = photoRoot.exportControllable.exporting(ids: photoIds)
        allIds.merge(other: newPhotoIds)

        let newTableIds =  tableRoot.exportControllable.exporting(ids: tableIds)
        allIds.merge(other: newTableIds)

        return allIds
    }
}
