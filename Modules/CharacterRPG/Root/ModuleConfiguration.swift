// @copyright André Trettin

import CoreRPG
import Foundation
import UniformTypeIdentifiers

@MainActor
public struct ModuleConfiguration: ModuleConfigurable, Sendable {
    public let module: NetworkModules = .value
    public let categoryTags: [ItemListCategory] = [.character, .gameMaster, .item, .monster]
    
    public let fileTypes: [UTType] = []
    public let filenameExtension: String = ""
    
    public let collectionCategory: ItemListCategory = .collection
    
    public let linkSelectionModel: ItemSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: true)
}
