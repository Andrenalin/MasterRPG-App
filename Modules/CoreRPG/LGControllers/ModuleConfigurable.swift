// @copyright André Trettin

import Foundation

public protocol ModuleConfigurable {
    var module: NetworkModules { get }
    var categoryTags: [ItemListCategory] { get }
}
