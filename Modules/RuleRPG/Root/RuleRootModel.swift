// @copyright André Trettin

import CoreData
import CoreRPG
import Observation

@MainActor @Observable
public final class RuleRootModel {
    @MainActor
    init(tagController: TagController) {
        let config = ModuleConfiguration()
        self.config = config

        let navigationModel = ModuleNavigationModel()
        self.navigationModel = navigationModel
        itemSelectionModel = ItemSelectionModel()
        linkSelectionModel = config.linkSelectionModel
        removeEntryListModel = RemoveEntryListModel()

        let searchModel = SearchModel(
            tagController: tagController,
            module: config.module,
            categoryTags: config.categoryTags
        )
        self.searchModel = searchModel
        let listDisplayModel = ListDisplayModel()
        self.listDisplayModel = listDisplayModel

        let itemController = ItemController(config: config)
        self.itemController = itemController
        let sheetController = SheetController(itemController: itemController)
        self.sheetController = sheetController
        let exportController = ExportController(itemController: itemController)
        self.exportController = exportController
        let gameController = GameController(
            itemController: itemController,
            exportController: exportController
        )
        self.gameController = gameController
        let linkController = LinkController(
            itemController: itemController,
            gameController: gameController
        )
        self.linkController = linkController
        let editController = EditController(
            itemController: itemController,
            tagController: tagController
        )
        self.editController = editController
        let importController = ImportController(
            itemController: itemController,
            editController: editController
        )
        self.importController = importController
        let searchController = SearchController(itemController: itemController)
        self.searchController = searchController
        viewController = ViewController()

        let folderListModel = FolderListModel(
            isSelectionMode: false,
            selection: [],
            navigationModel: navigationModel
        )
        let folderListController = FolderListController(
            listModel: folderListModel,
            listDisplayModel: listDisplayModel,
            itemControllable: itemController,
            searchRootControllable: SearchListController(
                searchController: searchController,
                searchModel: searchModel,
                listDisplayModel: listDisplayModel
            )
        )
        self.folderListController = folderListController

        let folderLinkModel = FolderListModel(
            isSelectionMode: false,
            selection: [],
            navigationModel: navigationModel
        )
        let linkDisplayModel = listDisplayModel.newListDisplayModel
        let folderLinkController = FolderListController(
            listModel: folderLinkModel,
            listDisplayModel: linkDisplayModel,
            itemControllable: itemController,
            searchRootControllable: SearchLinkController(
                searchController: searchController,
                searchModel: searchModel.newSearchModel,
                listDisplayModel: linkDisplayModel
            )
        )
        self.folderLinkController = folderLinkController

        editorLinkModel = EditorLinkModel(
            folderListController: folderLinkController,
            adventureSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: true),
            mapSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: true),
            pdfSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: true),
            ruleSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: true),
            tableSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: true),
            firstRow: [.rule, .adventure, .value, .dice, .table, .pdf],
            secondRow: [.map, .photo, .audio, .space, .weather],
            selection: .rule
        )
        openFileWindowModel = OpenFileWindowModel(
            windowId: NetworkModules.rule.viewerWindowId,
            canShow: true
        ) { RuleViewerRoute.viewer($0) }

        rootController = ItemRootController(
            rootManager: nil,
            config: config,
            navigationModel: navigationModel,
            inspectorEditorLinkModel: editorLinkModel,
            openFileWindowModel: openFileWindowModel,
            itemSelectionModel: itemSelectionModel,
            removeEntryListModel: removeEntryListModel,
            cacheControllable: nil,
            editControllable: editController,
            exportControllable: exportController,
            gameControllable: gameController,
            importControllable: importController,
            itemControllable: itemController,
            linkControllable: linkController,
            folderListControllable: folderListController,
            folderLinkControllable: folderLinkController,
            searchControllable: searchController,
            sheetControllable: sheetController,
            viewControllable: viewController
        )
    }

    public func setUp(
        context: NSManagedObjectContext?,
        batchContext: NSManagedObjectContext?,
        rootManager: RootManager,
        adventureRootControllable: any RootExportControllable,
        linkRegisterController: LinkRegisterController
    ) {
        rootController.rootManager = rootManager
        itemController.itemDataModel.dataController = context.map {
            DataController(
                context: $0,
                batchContext: batchContext,
                token: config.module.token
            )
        }
        itemController.itemDataModel.linkRegisterController = linkRegisterController
        exportController.hubControllable = adventureRootControllable
        exportController.setUp(rootManager: rootManager)
        linkController.setUp(rootManager: rootManager)
        editorLinkModel.rootManager = rootManager
        editController.editorModel.sheetRootModel = SheetRootModel(
            rootManager: rootManager,
            linkControllable: linkController,
            sheetControllable: sheetController,
            itemId: UUID(),
            isEditor: true,
            editorModel: editController.editorModel.sheetEditorModel
        )

        syncTask?.cancel()
        syncTask = nil
        syncDataController = nil
        if let dataControllable = itemController.itemDataModel.dataController, let context {
            let controller = SyncDataController(
                context: context,
                dataControllable: dataControllable,
                itemController: itemController
            )
            syncDataController = controller
            syncTask = controller.start()
        }
    }

    public let config: ModuleConfiguration
    public var navigationModel: ModuleNavigationModel
    @ObservationIgnored public var itemSelectionModel: ItemSelectionModel
    @ObservationIgnored public var linkSelectionModel: ItemSelectionModel
    public let removeEntryListModel: RemoveEntryListModel

    let searchModel: SearchModel
    let listDisplayModel: ListDisplayModel
    let itemController: ItemController
    let sheetController: SheetController
    @ObservationIgnored var exportController: ExportController
    @ObservationIgnored let gameController: GameController
    @ObservationIgnored let importController: ImportController
    @ObservationIgnored let linkController: LinkController
    @ObservationIgnored let searchController: SearchController
    @ObservationIgnored let editController: EditController
    @ObservationIgnored public let viewController: ViewController
    @ObservationIgnored let folderListController: FolderListController
    @ObservationIgnored let folderLinkController: FolderListController
    @ObservationIgnored var syncDataController: SyncDataController?
    @ObservationIgnored var syncTask: Task<Void, Never>?
    @ObservationIgnored let editorLinkModel: EditorLinkModel
    @ObservationIgnored public let openFileWindowModel: OpenFileWindowModel
    @ObservationIgnored public let rootController: ItemRootController
}

extension RuleRootModel: ItemRootControllable {
    public var currentSelectedItemId: UUID? { folderListController.listModel.selectedItemId }
    public var rootManager: RootManager? { rootController.rootManager }
    public var configurable: any ModuleConfigurable { config }
    public var cacheControllable: (any ImageCacheControllable)? { nil }
    public var editControllable: any EditControllable { editController }
    public var exportControllable: any ExportControllable { exportController }
    public var gameControllable: any GameControllable { gameController }
    public var importControllable: any ImportControllable { importController }
    public var itemControllable: any ItemControllable { itemController }
    public var linkControllable: any LinkControllable { linkController }
    public var folderListControllable: any FolderListControllable { folderListController }
    public var folderLinkControllable: any FolderListControllable { folderLinkController }
    public var inspectorEditorLinkModel: EditorLinkModel? { editorLinkModel }
    public var searchControllable: any SearchControllable { searchController }
    public var sheetControllable: any SheetControllable { sheetController }
    public var viewControllable: any ViewControllable { viewController }
}

extension RuleRootModel: RootExportControllable {}

public extension RuleRootModel {
    func listItems() -> [RuleModel] {
        itemController.itemDataModel.items.map { itemController.itemOrEmpty(for: $0) }
    }

    func itemDataCleanup() async throws {
        for itemId in itemController.itemDataModel.items {
            guard let model = await itemController.item(for: itemId) else { continue }
            if model.displayState == DisplayStateMask.totalHidden.rawValue {
                await editController.delete(itemId: model.id)
            }
        }
    }

    func checkFolders(reportModel: ValidateRepairModel) async {
        let controller = ConvertController(
            itemController: itemController,
            editController: editController
        )
        await controller.repairHiddenAndFolders(reportModel: reportModel)
    }

    func validateLinks(reportModel: ValidateRepairModel) async {
        await linkController.validateLinks(reportModel: reportModel)
    }
}
