// @copyright André Trettin

import Foundation

/// A fully self-contained, in-memory-only editing session for
/// `SheetRootEditorView` — no Core Data, no CloudKit, nothing to
/// accidentally reach either, because the capability is structurally
/// absent from every controller involved (`SimpleItemController.dataControllable`
/// is always `nil`).
///
/// The session's own root header can't be edited in place — that's a
/// structural limit of `SheetRootView`'s root name row, not something this
/// stack can work around — so what's actually shown by `sheetRootModel` is
/// a *wrapping* root with exactly one entry (an entry, unlike a root
/// header, is genuinely editable). That one entry links (`childId`) to a
/// second, real item — `resultItemId` — which holds whatever entries the
/// caller seeds via `editController`/`resultItemId`, nested one level
/// underneath. `Modules/CoreRPG/Simple/SimpleSheetController.swift` is what
/// resolves that link into a nested sheet, mirroring
/// `Modules/CharacterRPG/Controller/SheetController.swift`'s `entry.valueId`
/// "group" pattern.
///
/// Any module can spin one of these up to let the user shape freeform
/// content with the real sheet-editing UI — add/edit/reorder/delete entries
/// — without persisting anything, then read `resultModel`/`currentModel`
/// back out to build its own real, persisted domain model from the result
/// (e.g. Character's `ValueModel`/`ValueEntryModel`).
///
/// Only `itemControllable`/`editControllable`/`linkControllable`/
/// `sheetControllable` are real (`SimpleItemController`/`SimpleEditController`/
/// `SimpleLinkController`/`SimpleSheetController`) — the peripheral
/// controllables `ItemRootController` also requires (export/game/import/
/// search/folder-list/view) are never exercised by a pure add/edit-entries
/// sheet session, so this reuses the existing internal `Fake*` equivalents
/// directly rather than duplicating them.
///
/// A consumer embedding `SheetRootEditorView` also needs to present
/// `EntryEditorView(rootManager: rootController.rootManager!, editorModel:
/// sheetEditorModel, linkTypes:)` as its own `.overlay(alignment: .center)`
/// — that overlay isn't part of `SheetRootEditorView`/`SheetRootView`
/// themselves; in the real app it's supplied by the ancestor
/// `ItemDetailContentView`, which this session has no equivalent of. See
/// `sheetEditorModel`'s doc comment for why it must be this exact instance.
@MainActor
public final class SimpleSheetEditingSession {
    /// - Parameters:
    ///   - name: Seeds the *wrapping entry's* name (the real, editable
    ///     stand-in for the root's own uneditable title) — not the root
    ///     item's own name, which is never shown or edited.
    public init(module: NetworkModules, name: String = "") {
        let config = SimpleModuleConfiguration(module: module)
        let itemDataModel = ItemDataModel(categoryTags: config.categoryTags)
        let linkRegisterController = LinkRegisterController(root: nil)
        let itemController = SimpleItemController(config: config, linkRegisterController: linkRegisterController, itemDataModel: itemDataModel)

        let rootItemId = UUID()
        // Shared with `SheetRootModel` below — see the type-level doc
        // comment on `sheetEditorModel` for why it must be this exact
        // instance.
        let sheetEditorModel = SheetEditorModel(itemId: rootItemId, module: module)
        let editController = SimpleEditController(
            itemControllable: itemController,
            tagController: TagController(),
            linkRegisterController: linkRegisterController,
            editorModel: ItemEditorModel(sheetEditorModel: sheetEditorModel)
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
        let sessionRootManager = RootManager.preview(fake: root)
        root.rootManager = sessionRootManager

        // The result item holds whatever the caller seeds afterward — the
        // actual outcome content. Registered before the wrapping root so
        // the root's one entry can link to it immediately.
        let resultItemId = UUID()
        itemController.resetModel(with: SimpleModel(id: resultItemId))

        let wrappingEntry = SimpleEntryModel(childId: resultItemId, name: name, content: "")
        itemController.resetModel(with: SimpleModel(id: rootItemId, entries: [wrappingEntry]))

        self.itemId = rootItemId
        self.resultItemId = resultItemId
        self.rootController = root
        self.itemController = itemController
        self.editController = editController
        self.sheetEditorModel = sheetEditorModel
        self.sheetRootModel = SheetRootModel(
            rootManager: sessionRootManager,
            linkControllable: linkController,
            sheetControllable: sheetController,
            itemId: rootItemId,
            isEditor: true,
            editorModel: sheetEditorModel
        )
    }

    /// The wrapping root's id — what `sheetRootModel` displays. Its own
    /// name/description are never shown or editable; only its one entry
    /// (linked to `resultItemId`) is.
    public let itemId: UUID

    /// The result item's id — seed its entries via `editController` (e.g.
    /// `editController.insertEntry(itemId: resultItemId, ...)`) to populate
    /// the actual outcome content, nested one level under the wrapping
    /// entry.
    public let resultItemId: UUID

    public let rootController: ItemRootController
    public let editController: SimpleEditController
    public let sheetRootModel: SheetRootModel

    /// Pass to `EntryEditorView(rootManager:editorModel:linkTypes:)` — see
    /// the type-level doc comment for why this exact instance matters.
    public let sheetEditorModel: SheetEditorModel

    private let itemController: SimpleItemController

    /// The wrapping root's current state — `entries.first?.name` is the
    /// real, editable title for the whole outcome (see the type-level doc
    /// comment).
    public var currentModel: SimpleModel? {
        itemController.itemSync(for: itemId)
    }

    /// The result item's current state, read back out once the user is
    /// done — e.g. to flatten its entries into a plain string, or to seed a
    /// real persisted domain model in another module.
    public var resultModel: SimpleModel? {
        itemController.itemSync(for: resultItemId)
    }
}
