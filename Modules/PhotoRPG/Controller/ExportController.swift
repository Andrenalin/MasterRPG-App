// @copyright André Trettin

import CoreRPG
import Foundation

struct ExportController: Sendable {
    @MainActor init(itemController: ItemController) {
        self.itemController = itemController
        self.exportModel = ExportModel()
    }

    let exportModel: ExportModel
    var hubControllable: any RootExportControllable {
        get {
            guard let hub = exportModel.hubControllable else {
                preconditionFailure("PhotoRPG export requires its Adventure export hub after setup.")
            }
            return hub
        }
        set { exportModel.hubControllable = newValue }
    }
    let itemController: ItemController
}

extension ExportController: ExportControllable {
    var itemControllable: any ItemControllable { itemController }

    // Deliberately does NOT use the shared `exportingSimpleEntries(itemIds:)`
    // default (see CoreRPG/Controllable/ExportControllable.swift): unlike
    // every "simple" module where an entry carries its own content and
    // `childId == id`, a `PhotoEntryModel`'s only payload is `photoId` — it's
    // purely a reference to another Photo item (e.g. an album/carousel
    // grouping). So even a non-container ("leaf") photo must still walk its
    // entries on export, or a referenced photo silently drops out. Same bug
    // class, same fix already applied to `AudioRPG.ExportController` for its
    // playlist tracks — see that file's comment for the CODE_AUDIT §5.1/§9.4
    // bisection that caught it there; this module was missed at the time.
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
