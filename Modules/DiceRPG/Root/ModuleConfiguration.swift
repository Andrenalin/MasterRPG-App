// @copyright André Trettin

import CoreRPG
import Foundation
import UniformTypeIdentifiers

@MainActor
public struct ModuleConfiguration: ModuleConfigurable, Sendable {
    public let module: NetworkModules = .dice
    public let categoryTags: [ItemListCategory] = [.rules, .table, .value]
    
    public let fileTypes: [UTType] = []
    public let filenameExtension: String = ""
    
    public let collectionCategory: ItemListCategory = .diceBag
    
    public let linkSelectionModel: ItemSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: true)
}
