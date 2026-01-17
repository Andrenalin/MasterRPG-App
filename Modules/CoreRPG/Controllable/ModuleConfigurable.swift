// @copyright André Trettin

import Foundation
import UniformTypeIdentifiers

public protocol ModuleConfigurable: Sendable {
    var module: NetworkModules { get }
    var categoryTags: [ItemListCategory] { get }
    
    var fileTypes: [UTType] { get }
    var filenameExtension: String { get }

    var collectionCategory: ItemListCategory { get }
    
    var linkSelectionModel: ItemSelectionModel { get }
}
