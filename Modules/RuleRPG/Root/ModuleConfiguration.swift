// @copyright André Trettin

import CoreRPG
import UniformTypeIdentifiers

@MainActor
public struct ModuleConfiguration: ModuleConfigurable, Sendable {
    public init() {}

    public let module: NetworkModules = .rule
    public let categoryTags: [ItemListCategory] = [.rules, .supplement, .item, .loot]
    public let fileTypes: [UTType] = []
    public let filenameExtension = ""
    public let collectionCategory: ItemListCategory = .bookshelf
    public let linkSelectionModel = ItemSelectionModel(
        selection: [],
        isSingleSelection: false,
        allowCollections: true,
        allowEntrySelection: true
    )
}

