// @copyright André Trettin

import AndrenalinKit
import Foundation
import TableRPG
import PhotoRPG
import DiceRPG

struct ExportController: Sendable {
    @MainActor
    init(root: CharacterRootModel, itemController: ItemController, gameExporter: Bool) {
        self.root = root
        self.itemController = itemController
        self.exportModel = ItemDataExportModel(gameExporter: gameExporter)
    }

    weak var root: CharacterRootModel!
    let itemController: ItemController

    public let exportModel: ItemDataExportModel
}

extension ExportController: ExportControllable {
    var itemControllable: any ItemControllable {
        itemController as (any ItemControllable)
    }

    public func exportingAll() -> ItemModuleIds {
        var allIds = root.photoRoot.exportControllable.exportingAll()
        allIds.merge(other: root.tableRoot.exportControllable.exportingAll())
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

            if let photoId = item.photoId, root.photoRoot.linkController.validateLink(itemId: photoId) {
                photoIds.insert(photoId)
            }
            photoIds.formUnion(item.photos.filter { root.photoRoot.linkController.validateLink(itemId: $0) })

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
                    if root.diceRoot.linkController.validateLink(itemId: $0.itemId) {
                        diceIds.insert($0.itemId)
                    }
                case .photo:
                    if root.photoRoot.linkController.validateLink(itemId: $0.itemId) {
                        photoIds.insert($0.itemId)
                    }
                case .table:
                    if root.tableRoot.linkController.validateLink(itemId: $0.itemId, entryId: nil) {
                        tableIds.insert($0.itemId)
                    }
                case .value:
                    if !(results.contains($0.itemId) || checkIds.contains($0.itemId)) && root.linkController.validateLink(itemId: $0.itemId) {
                        checkIds.append($0.itemId)
                    }
                default:
                    print("*** ERROR table \(item.name) export is not handling link \($0)")
                }
            }
        }
        var allIds = itemIds
        allIds.ids[itemController.itemDataModel.networkModule] = Array(results)

        let newDiceIds = root.diceRoot.exportControllable.exporting(ids: diceIds)
        allIds.merge(other: newDiceIds)

        let newPhotoIds = root.photoRoot.exportControllable.exporting(ids: photoIds)
        allIds.merge(other: newPhotoIds)

        let newTableIds = root.tableRoot.exportControllable.exporting(ids: tableIds)
        allIds.merge(other: newTableIds)

        return allIds
    }
}
