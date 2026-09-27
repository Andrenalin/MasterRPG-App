// @copyright André Trettin

import Foundation

/// Generic replacement for the near-identical per-module `ItemController` structs — a
/// module with no extra state beyond `config`/`collectionCategory`/`itemDataModel` (no
/// `cacheController`, `fileUrlDataController`, or extra init parameters like `tableRoot`)
/// needs only a one-line adoption:
/// ```swift
/// typealias ItemController = GenericItemController<AdventureModel>
/// ```
/// Modules with extra stored state (file-backed modules' `fileUrlDataController`/
/// `cacheController`, `CharacterRPG`'s `tableRoot`, `MapRPG`'s `cacheController`,
/// `DiceRPG`'s `diceBag`, …) still provide their own bespoke `ItemController`, since a
/// stored property can't be added later via extension. See CODE_AUDIT §9.3.
public struct GenericItemController<
    Model: ItemDataAccessible & ItemDiffComparable & ItemDuplicatable & ItemLinkRegistrable & Identifiable & Equatable & Hashable & Codable & ModelType
>: Sendable {
    @MainActor public init(config: ModuleConfigurable) {
        self.config = config
        self.itemDataModel = ItemDataModel(categoryTags: config.categoryTags)
        self.collectionCategory = config.collectionCategory
    }

    public let config: ModuleConfigurable
    public let collectionCategory: ItemListCategory
    public let itemDataModel: ItemDataModel
}

extension GenericItemController: ItemControllable {
    @MainActor public var dataControllable: (any DataPersistenceControllable)? { itemDataModel.dataController }
}
