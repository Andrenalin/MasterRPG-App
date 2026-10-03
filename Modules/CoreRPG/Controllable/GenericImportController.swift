// @copyright André Trettin

import Foundation

/// Generic replacement for the byte-identical per-module `ImportController` structs —
/// `struct ImportController: Sendable { let itemController: ItemController; let editController:
/// EditController }` plus an `ImportControllable` forwarding extension, hand-copied into 10
/// modules with only the concrete `ItemController`/`EditController` types differing. A module
/// adopts this with a single line:
/// ```swift
/// typealias ImportController = GenericImportController<ItemController, EditController>
/// ```
/// `AdventureRPG` keeps its own `ImportController` for its additional and final module
/// imports. See CODE_AUDIT §9.2, CODE_AUDIT_Folder §9.3.
public struct GenericImportController<Item: ItemControllable & Sendable, Edit: EditControllable & Sendable>: ImportControllable, Sendable {
    @MainActor public init(itemController: Item, editController: Edit) {
        self.itemController = itemController
        self.editController = editController
    }

    public let itemController: Item
    public let editController: Edit

    public var itemControllable: any ItemControllable { itemController }
    public var editControllable: any EditControllable { editController }
}
