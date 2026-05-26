// @copyright André Trettin

import CoreRPG
import Foundation
import UniformTypeIdentifiers

@MainActor
public struct ModuleConfiguration: ModuleConfigurable, Sendable {
    public let module: NetworkModules = .table
    public let categoryTags: [ItemListCategory] = [.rules, .loot, .supplement, .generator]

    public let fileTypes: [UTType] = []
    public let filenameExtension: String = ""

    public let collectionCategory: ItemListCategory = .bookshelf

    public let linkSelectionModel: ItemSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: true)
}
