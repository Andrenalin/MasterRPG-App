// @copyright André Trettin

import CoreRPG
import Foundation

public struct ModuleConfiguration: ModuleConfigurable, Sendable {
    public let module: NetworkModules = .photo
    public let categoryTags: [ItemListCategory] = [.building, .item, .supplement]
}
