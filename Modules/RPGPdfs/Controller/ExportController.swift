// @copyright André Trettin

import AndrenalinKit
import Foundation

struct ExportController: Sendable {
    @MainActor
    init(root: PdfRoot, gameExporter: Bool) {
        self.root = root
        self.exportModel = ItemDataExportModel(gameExporter: gameExporter)
    }

    weak var root: PdfRoot!
    public let exportModel: ItemDataExportModel
}

extension ExportController: ExportControllable {
    var itemControllable: any ItemControllable {
        root.itemController as (any ItemControllable)
    }
    var fileControllable: (any FileControllable)? {
        root.fileController
    }

    public func exporting(itemIds: ItemModuleIds) -> ItemModuleIds {
        let checkIds = itemIds.ids[root.itemController.itemDataModel.networkModule, default: []]
        let results = checkIds.compactMap { root.itemController.itemSync(for: $0)?.id }
        var allIds = itemIds
        allIds.ids[root.itemController.itemDataModel.networkModule] = results
        return allIds
    }
}
