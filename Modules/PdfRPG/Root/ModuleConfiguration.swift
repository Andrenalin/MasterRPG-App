// @copyright André Trettin

import CoreRPG
import Foundation
import UniformTypeIdentifiers

@MainActor
public struct ModuleConfiguration: ModuleConfigurable, Sendable {
    public let module: NetworkModules = .pdf
    public let categoryTags: [ItemListCategory] = [.adventure, .character, .rules, .supplement]
    
    public let fileTypes: [UTType] = [.pdf]
    public let filenameExtension: String = "pdf"
    
    public let collectionCategory: ItemListCategory = .bookshelf
    
    public let linkSelectionModel: ItemSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: true)
}
