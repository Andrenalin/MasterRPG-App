// @copyright André Trettin

import Foundation

/// A fully self-contained, in-memory-only editing session for
/// `SheetRootEditorView` — no Core Data, no CloudKit, nothing to
/// accidentally reach either, because the capability is structurally
/// absent from every controller involved (`SimpleItemController.dataControllable`
/// is always `nil`).
///
/// Any module can spin one of these up to let the user shape freeform
/// content with the real sheet-editing UI — add/edit/reorder/delete entries
/// — without persisting anything, then read `currentModel` back out to
/// build its own real, persisted domain model from the result (e.g.
/// Character's `ValueModel`/`ValueEntryModel`).
///
/// Only `itemControllable`/`editControllable`/`linkControllable`/
/// `sheetControllable` are real (`SimpleItemController`/`SimpleEditController`/
/// `SimpleLinkController`/`SimpleSheetController`) — the peripheral
/// controllables `ItemRootController` also requires (export/game/import/
/// search/folder-list/view) are never exercised by a pure add/edit-entries
/// sheet session, so this reuses the existing internal `Fake*` equivalents
/// directly rather than duplicating them.
@MainActor
public final class SimpleSheetEditingSession {
    public init(module: NetworkModules, name: String = "", description: String = "") {
        let config = SimpleModuleConfiguration(module: module)
        let itemDataModel = ItemDataModel(categoryTags: config.categoryTags)
        let linkRegisterController = LinkRegisterController(root: nil)
        let itemController = SimpleItemController(config: config, linkRegisterController: linkRegisterController, itemDataModel: itemDataModel)
        let editController = SimpleEditController(
            itemControllable: itemController,
            tagController: TagController(),
            linkRegisterController: linkRegisterController,
            editorModel: ItemEditorModel(sheetEditorModel: SheetEditorModel())
        )
        let linkController = SimpleLinkController(itemControllable: itemController)
        let sheetController = SimpleSheetController(itemController: itemController)

        let root = ItemRootController(
            config: config,
            navigationModel: ModuleNavigationModel(),
            inspectorEditorLinkModel: nil,
            openFileWindowModel: OpenFileWindowModel(),
            itemSelectionModel: ItemSelectionModel(),
            removeEntryListModel: RemoveEntryListModel(),
            cacheControllable: nil,
            editControllable: editController,
            exportControllable: FakeExportController.fake,
            gameControllable: FakeGameController.fake,
            importControllable: FakeImportController.fake,
            itemControllable: itemController,
            linkControllable: linkController,
            folderListControllable: FakeFolderListController.fake,
            folderLinkControllable: FakeFolderListController.fake,
            searchControllable: FakeSearchController.fake,
            sheetControllable: sheetController,
            viewControllable: FakeViewController()
        )
        // A plain, non-DEBUG-gated public API (`Modules/CoreRPG/Controllable/RootManager.swift`)
        // that fans one root out to every module slot — exactly what a
        // standalone session with no other modules to link to needs.
        root.rootManager = RootManager.preview(fake: root)

        let itemId = UUID()
        itemController.resetModel(with: SimpleModel(id: itemId, name: name, description: description))

        self.itemId = itemId
        self.rootController = root
        self.itemController = itemController
        self.editController = editController
        self.sheetRootModel = SheetRootModel(
            rootManager: root.rootManager!,
            linkControllable: linkController,
            sheetControllable: sheetController,
            itemId: itemId,
            isEditor: true
        )
    }

    public let itemId: UUID
    public let rootController: ItemRootController
    public let editController: SimpleEditController
    public let sheetRootModel: SheetRootModel

    private let itemController: SimpleItemController

    /// The current state of the edited item, read back out once the user is
    /// done — e.g. to flatten its entries into a plain string, or to seed a
    /// real persisted domain model in another module.
    public var currentModel: SimpleModel? {
        itemController.itemSync(for: itemId)
    }
}
