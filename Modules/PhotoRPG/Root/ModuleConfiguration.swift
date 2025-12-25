// @copyright André Trettin

import CoreRPG
import Foundation
import UniformTypeIdentifiers

@MainActor
public struct ModuleConfiguration: ModuleConfigurable, Sendable {
    public let module: NetworkModules = .photo
    public let categoryTags: [ItemListCategory] = [.adventure, .map, .value, .weather]
    
    public let fileTypes: [UTType] = [.image]
    public let filenameExtension: String = "jpg"
    
    public let collectionCategory: ItemListCategory = .album
    
    public let linkSelectionModel: ItemSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: true)
}
