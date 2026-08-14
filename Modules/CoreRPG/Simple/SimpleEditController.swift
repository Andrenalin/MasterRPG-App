// @copyright André Trettin

import SwiftUI

/// An `EditControllable` + `EntryDataEditable` conformer for
/// ``SimpleSheetEditingSession``. Almost none of `EntryDataEditable` needs
/// overriding here: `addNewEntry`, `add(entry:...)`, `remove(...)`,
/// `move(...)`, `update(itemId:entryId:name:content:)`, `insertEntry(...)`,
/// `copy(...)` are all generic protocol-extension defaults in
/// `Modules/CoreRPG/ItemList/EntryDataEditable.swift` that operate purely on
/// `editModel(for:)` → `save(...)` → `saveChanges(...)` →
/// `itemControllable.replace(...)` — since `SimpleModel.replace(with:)` is a
/// real implementation (unlike `Modules/CoreRPG/Fake/FakeItemModel.swift`'s
/// stub), those defaults genuinely add/edit/remove/reorder entries here with
/// zero extra code.
///
/// Only the handful of requirements with no extension default need real
/// bodies below — and `create(name:content:)` in particular must actually
/// use its arguments: `insertEntry(...)` calls it directly to seed real
/// content, so a stub here (like `FakeEditController.create`, which
/// discards its arguments) would silently drop whatever text the caller
/// meant to seed.
public struct SimpleEditController: EditControllable {
    public init(itemControllable: any ItemControllable, tagController: TagController, linkRegisterController: LinkRegisterController, editorModel: ItemEditorModel) {
        self.itemControllable = itemControllable
        self.tagController = tagController
        self.linkRegisterController = linkRegisterController
        self.editorModel = editorModel
    }

    public typealias Model = SimpleModel

    public let itemControllable: any ItemControllable
    public let tagController: TagController
    public let linkRegisterController: LinkRegisterController
    public let editorModel: ItemEditorModel
}

extension SimpleEditController: EntryDataEditable {
    public var linkModules: [NetworkModules] { [] }

    public func linkSelectionDestination(itemRowModel: ItemRowModel) -> any NavigationDestination {
        InternalRoute.removeAlert
    }

    public func quickEditorDestination(itemRowModel: ItemRowModel) -> any NavigationDestination {
        InternalRoute.removeAlert
    }

    public func create(name: String, content: String) -> SimpleEntryModel {
        SimpleEntryModel(name: name, content: content)
    }

    /// No import feature exists for a `SimpleModel`, so there's nothing to
    /// reconcile against — passing `entries` through unchanged is the
    /// correct answer, not a stand-in for missing logic.
    public func merge(itemId: UUID, entries: [SimpleEntryModel]) -> [SimpleEntryModel] {
        entries
    }

    public func merge(itemId: UUID, entries: [SimpleEntryModel], recoverEntries: [ItemRowModel]?, forceSave: Bool) -> [ItemRowModel] {
        []
    }
}
