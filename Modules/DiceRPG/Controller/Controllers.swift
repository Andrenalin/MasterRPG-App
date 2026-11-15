// @copyright André Trettin

import CoreRPG
import Foundation

/// See CODE_AUDIT §9.2 — genericized in `GenericImportController` (CoreRPG); this module needs
/// no behavior beyond the shared default.
typealias ImportController = GenericImportController<ItemController, EditController>

/// The shared search of `GenericSearchController` (CoreRPG); this module adds nothing to it.
typealias SearchController = GenericSearchController<ItemController>

/// A result category that is exported with one dice for the share in flight only, instead of being
/// written onto the shared model for the duration of the export. Task-local, so two overlapping
/// shares of the same dice each export their own category. See CODE_AUDIT_26 §3.1.
struct DiceShareOverride: Sendable {
    let itemId: UUID
    let resultCategory: ResultCategory?

    @TaskLocal static var current: DiceShareOverride?
}

/// The shared export (`GenericExportController`'s behaviour) plus the per-share result category of
/// `DiceShareOverride`. Only a package for players is affected; a library export or Save Game
/// writes the dice as stored.
struct ExportController: ExportModelBacked, Sendable {
    @MainActor init(itemController: ItemController) {
        self.itemController = itemController
        self.exportModel = ExportModel()
    }

    let exportModel: ExportModel
    let itemController: ItemController

    var itemControllable: any ItemControllable { itemController }

    @MainActor func playerExportData(for itemId: UUID) throws -> Data? {
        guard let override = DiceShareOverride.current, override.itemId == itemId,
              let item = itemController.itemSync(for: itemId) else { return nil }
        let shared = item.copy()
        shared.resultCategory = override.resultCategory
        return try JSONCoding.encoder.encode(shared)
    }
}
