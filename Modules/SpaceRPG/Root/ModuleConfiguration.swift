// @copyright André Trettin

import CoreRPG
import Foundation
import UniformTypeIdentifiers

@MainActor
public struct ModuleConfiguration: ModuleConfigurable, Sendable {
    public let module: NetworkModules = .space
    public let categoryTags: [ItemListCategory] = [.building, .item, .supplement]
    
    public let fileTypes: [UTType] = [.usdz]
    public let filenameExtension: String = "usdz"
    
    public let collectionCategory: ItemListCategory = .album
    
    public let linkSelectionModel: ItemSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: true)
}
