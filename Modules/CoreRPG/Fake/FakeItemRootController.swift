// @copyright André Trettin

import Foundation

/// A fresh, internally consistent controller graph for one preview or test.
///
/// Keep one fixture in local scope when a view needs multiple controllers so
/// those values share the same models instead of crossing fixture boundaries.
@MainActor
struct FakeItemRootControllerFixture {
    init(
        sharingViewType: SharingViewType = .none,
        dataControllable: (any DataPersistenceControllable)? = nil
    ) {
        let config = FakeModuleConfiguration()
        let navigationModel = ModuleNavigationModel()
        let linkRegisterController = LinkRegisterController(root: nil)
        let itemDataModel = ItemDataModel()
        let itemController = FakeItemController(
            config: config,
            dataControllable: dataControllable,
            linkRegisterController: linkRegisterController,
            itemDataModel: itemDataModel
        )
        let tagController = TagController()
        let editController = FakeEditController(
            itemControllable: itemController,
            tagController: tagController,
            linkRegisterController: linkRegisterController,
            editorModel: ItemEditorModel(sheetEditorModel: SheetEditorModel()),
            cacheItemListModel: CacheItemListModel()
        )
        let exportController = FakeExportController(itemControllable: itemController)
        let importController = FakeImportController(
            itemControllable: itemController,
            editControllable: editController
        )
        let gameController = FakeGameController(
            itemControllable: itemController,
            exportControllable: exportController,
            importControllable: importController,
            gameModel: ItemGameModel(itemDataModel: itemDataModel)
        )
        let linkController = FakeLinkController(itemControllable: itemController)
        let searchModel = SearchModel(
            tagController: tagController,
            module: config.module,
            categoryTags: config.categoryTags
        )
        let searchController = FakeSearchController(
            searchModel: searchModel,
            itemControllable: itemController
        )
        let folderListController = FakeFolderListController(
            itemControllable: itemController,
            listModel: FolderListModel(navigationModel: navigationModel),
            searchModel: searchModel,
            searchRootControllable: searchController
        )
        let sheetController = FakeSheetController()
        let root = ItemRootController(
            config: config,
            navigationModel: navigationModel,
            inspectorEditorLinkModel: nil,
            openFileWindowModel: OpenFileWindowModel(),
            itemSelectionModel: ItemSelectionModel(),
            removeEntryListModel: RemoveEntryListModel(),
            cacheControllable: nil,
            editControllable: editController,
            exportControllable: exportController,
            gameControllable: gameController,
            importControllable: importController,
            itemControllable: itemController,
            linkControllable: linkController,
            folderListControllable: folderListController,
            folderLinkControllable: folderListController,
            searchControllable: searchController,
            sheetControllable: sheetController,
            viewControllable: FakeViewController(sharingViewType: sharingViewType)
        )
        root.rootManager = RootManager.preview(fake: root)
        exportController.hubControllable = FakeRootController(
            exportControllable: exportController,
            importControllable: importController
        )

        self.root = root
        self.editController = editController
        self.exportController = exportController
        self.gameController = gameController
        self.importController = importController
        self.itemController = itemController
        self.linkController = linkController
        self.folderListController = folderListController
        self.searchController = searchController
        self.sheetController = sheetController
        self.sheetRootModel = SheetRootModel.previewFixture(root: root)
    }

    let root: ItemRootController
    let editController: FakeEditController
    let exportController: FakeExportController
    let gameController: FakeGameController
    let importController: FakeImportController
    let itemController: FakeItemController
    let linkController: FakeLinkController
    let folderListController: FakeFolderListController
    let searchController: FakeSearchController
    let sheetController: FakeSheetController
    let sheetRootModel: SheetRootModel
}

public extension ItemRootController {
    /// Builds an isolated controller graph for previews and tests.
    ///
    /// Every call owns fresh mutable models. Keep the returned root in a local
    /// value when a preview passes more than one controller from the graph.
    @MainActor static func previewFixture(
        sharingViewType: SharingViewType = .none,
        dataControllable: (any DataPersistenceControllable)? = nil
    ) -> ItemRootController {
        FakeItemRootControllerFixture(
            sharingViewType: sharingViewType,
            dataControllable: dataControllable
        ).root
    }

    /// Compatibility spelling for existing test and preview call sites.
    /// Unlike the previous `static let`, this returns a fresh graph per access.
    @MainActor static var fake: ItemRootController {
        previewFixture()
    }
}
