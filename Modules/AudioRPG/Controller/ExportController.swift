// @copyright André Trettin

import CoreRPG
import Foundation
import Observation

struct ExportController: Sendable {
    @MainActor init(itemController: ItemController) {
        self.itemController = itemController
        self.exportModel = ExportModel()
    }

    let exportModel: ExportModel
    let itemController: ItemController
}

extension ExportController: ExportModelBacked {
    var itemControllable: any ItemControllable { itemController }

    // Deliberately does NOT use the shared `exportingSimpleEntries(itemIds:)`
    // default (see CoreRPG/Controllable/ExportControllable.swift): unlike
    // every other "simple" module, an Audio item's own `entries` aren't
    // cross-references — they're the tracks that make up its playlist (see
    // `GameController.fetchPlaylist(id:seenIds:)`), so even a non-container
    // ("leaf") item must still walk them on export. Adding the
    // `specialCategory` guard here regressed a real playlist export/import
    // round trip (caught by `MasterPlayerControllerTests.handleAudioPLayList`)
    // — confirmed by bisection while fixing CODE_AUDIT §5.1/§9.4.
    @MainActor public func exporting(itemIds: ItemModuleIds) -> ItemModuleIds {
        let results = bfsExportResults(seedIds: itemIds.ids[itemController.config.module, default: []]) { id in
            guard let item = itemController.itemSync(for: id) else { return nil }
            return item.entries.compactMap { entryId in
                itemController.itemSync(for: entryId.childId) != nil ? entryId.childId : nil
            }
        }
        return finalizeExportResults(results, into: itemIds)
    }
}
