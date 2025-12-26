// @copyright André Trettin

import CoreRPG
import Foundation
import UniformTypeIdentifiers

@MainActor
public struct ModuleConfiguration: ModuleConfigurable, Sendable {
    public let module: NetworkModules = .audio
    public let categoryTags: [ItemListCategory] = [.music, .playlist, .sound]
    
    public let fileTypes: [UTType] = [.audio]
    public let filenameExtension: String = "m4a"
    
    public let collectionCategory: ItemListCategory = .playlist
    
    public let linkSelectionModel: ItemSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: true)
}
