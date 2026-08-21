// @copyright André Trettin

import Foundation

/// Generic replacement for the byte-identical per-module `ExportController` structs — a module
/// with no per-item companion assets beyond its own item tree needs only `let itemController`
/// and `ExportModelBacked`'s free `exporting(itemIds:)` default. A module adopts this with a
/// single line:
/// ```swift
/// typealias ExportController = GenericExportController<ItemController>
/// ```
/// Modules with companion assets to also collect (e.g. `CharacterRPG`'s `diceId`/`photoId`,
/// `MapRPG`'s `mapPins`) still provide their own bespoke `ExportController`, since they override
/// `exporting(itemIds:)` beyond this generic default. See CODE_AUDIT §9.2.
public struct GenericExportController<Item: ItemControllable & Sendable>: ExportModelBacked, Sendable {
    @MainActor public init(itemController: Item) {
        self.itemController = itemController
        self.exportModel = ExportModel()
    }

    public let exportModel: ExportModel
    public let itemController: Item

    public var itemControllable: any ItemControllable { itemController }
}
