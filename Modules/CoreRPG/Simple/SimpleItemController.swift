// @copyright André Trettin

import Foundation

/// An `ItemControllable` conformer with no persistence layer at all —
/// `dataControllable` is always `nil`, so every default-implemented method
/// on `ItemControllable` (`replace`, `addNew`, `delete`, `save`, ...) that
/// guards on it (`try? await dataControllable?...`) is a pure in-memory
/// operation. Nothing here can reach Core Data or CloudKit; the capability
/// is structurally absent, not switched off.
public struct SimpleItemController: ItemControllable {
    public init(config: any ModuleConfigurable, linkRegisterController: LinkRegisterController, itemDataModel: ItemDataModel) {
        self.config = config
        self.linkRegisterController = linkRegisterController
        self.itemDataModel = itemDataModel
    }

    public typealias Model = SimpleModel

    public let config: any ModuleConfigurable
    public var dataControllable: (any DataPersistenceControllable)? { nil }
    public let linkRegisterController: LinkRegisterController
    public let itemDataModel: ItemDataModel
}
