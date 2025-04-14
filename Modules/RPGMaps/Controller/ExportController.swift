// @copyright André Trettin

import AndrenalinKit
import Foundation

struct ExportController: Sendable {
    @MainActor
    init(root: MapRoot, itemController: ItemController, gameExporter: Bool) {
        self.root = root
        self.itemController = itemController
        self.exportModel = ItemDataExportModel(gameExporter: gameExporter)
    }

    weak var root: MapRoot!
    let itemController: ItemController

    public let exportModel: ItemDataExportModel
}

extension ExportController: ExportControllable {
    var itemControllable: any ItemControllable {
        itemController as (any ItemControllable)
    }

    public func exportingAll() -> ItemModuleIds {
        var itemIds = ItemModuleIds(dictionary: [itemController.itemDataModel.networkModule: itemController.itemDataModel.items.map { $0 }])

        if !exportModel.gameExporter {
            itemIds.merge(other: root.audioRoot.exportControllable.exportingAll())
            itemIds.merge(other: root.diceRoot.exportControllable.exportingAll())
            itemIds.merge(other: root.pdfRoot.exportControllable.exportingAll())
            itemIds.merge(other: root.photoRoot.exportControllable.exportingAll())
            itemIds.merge(other: root.tableRoot.exportControllable.exportingAll())
            itemIds.merge(other: root.valueRoot.exportControllable.exportingAll())
        }
        return itemIds
    }
    
    public func exporting(itemIds: ItemModuleIds) -> ItemModuleIds {
        var checkIds = itemIds.ids[itemController.itemDataModel.networkModule, default: []]
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

            photoIds.formUnion(item.mapPins.compactMap { $0.photoId }.compactMap { root.photoRoot.linkController.validateLink(itemId: $0) ? $0 : nil })
            if let photoId = item.photoId, root.photoRoot.linkController.validateLink(itemId: photoId) {
                photoIds.insert(photoId)
            }

            let links = item.entries.flatMap {
                let text = $0.content
                return LinkReplaceController.links(for: text)
            }

            links.forEach {
                switch $0.module {
                case .audio:
                    if root.audioRoot.linkController.validateLink(itemId: $0.itemId) {
                        audioIds.insert($0.itemId)
                    }
                case .dice:
                    if root.diceRoot.linkController.validateLink(itemId: $0.itemId) {
                        diceIds.insert($0.itemId)
                    }
                case .map:
                    if !(results.contains($0.itemId) || checkIds.contains($0.itemId)) && root.linkController.validateLink(itemId: $0.itemId) {
                        checkIds.append($0.itemId)
                    }
                case .photo:
                    if root.photoRoot.linkController.validateLink(itemId: $0.itemId) {
                        photoIds.insert($0.itemId)
                    }
                case .table:
                    if root.tableRoot.linkController.validateLink(itemId: $0.itemId) {
                        tableIds.insert($0.itemId)
                    }
                case .value:
                    if root.valueRoot.linkController.validateLink(itemId: $0.itemId) {
                        valueIds.insert($0.itemId)
                    }
                default:
                    print("*** ERROR table \(item.name) export is not handling link \($0)")
                }
            }
        }        
        var allIds = itemIds
        allIds.ids[itemController.itemDataModel.networkModule] = Array(results)
        let newAudioIds = root.audioRoot.exportControllable.exporting(ids: audioIds)
        allIds.merge(other: newAudioIds)
        let newDiceIds = root.diceRoot.exportControllable.exporting(ids: diceIds)
        allIds.merge(other: newDiceIds)
        let newPhotoIds = root.photoRoot.exportControllable.exporting(ids: photoIds)
        allIds.merge(other: newPhotoIds)
        let newTableIds = root.tableRoot.exportControllable.exporting(ids: tableIds)
        allIds.merge(other: newTableIds)
        let newValueIds = root.valueRoot.exportControllable.exporting(ids: valueIds)
        allIds.merge(other: newValueIds)
        return allIds
    }
}
