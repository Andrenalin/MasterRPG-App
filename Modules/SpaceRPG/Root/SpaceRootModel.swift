// @copyright André Trettin

import CoreRPG
import CoreData
import SwiftData
import SwiftUI

@MainActor @Observable
public final class SpaceRootModel {
    @MainActor init(tagController: TagController) {
        self.tagController = tagController

        let config = ModuleConfiguration()
        self.config = config

        self.itemSelectionModel = ItemSelectionModel()
        self.navigationModel = ModuleNavigationModel()
        self.linkSelectionModel = config.linkSelectionModel

        self.searchModel = SearchModel(tagController: tagController, module: config.module, categoryTags: config.categoryTags)
        self.listDisplayModel = ListDisplayModel()

        let itemController = ItemController(config: config)
        self.itemController = itemController
        self.sheetController = SheetController(itemController: itemController)
    }

    @MainActor public func setUp(context: NSManagedObjectContext?, batchContext: NSManagedObjectContext?, rootManager: RootManager, adventureRootControllable: any RootExportControllable, linkRegisterController: LinkRegisterController) {
        self.context = context
        self.batchContext = batchContext
        self.rootManager = rootManager
        self._adventureRootControllable = adventureRootControllable
        self._linkRegisterController = linkRegisterController

        _importController = nil
        _searchController = nil
        _folderListController = nil
        _folderLinkController = nil
        _rootController = nil

        itemController.itemDataModel.dataController = context.map { DataController(context: $0, batchContext: batchContext, token: config.module.token) }
        itemController.itemDataModel.linkRegisterController = linkRegisterController

        _exportController = ExportController(hubControllable: adventureRootControllable, itemController: itemController)
        _gameController = GameController(itemController: itemController, exportController: exportController)
        _linkController = LinkController(itemController: itemController, gameController: gameController)
        _editController = EditController(rootManager: rootManager, itemController: itemController, linkController: linkController, sheetController: sheetController, tagController: searchModel.tagController)

        syncTask?.cancel()
        if let dataControllable = itemController.itemDataModel.dataController, let context {
            let controller = SyncDataController(context: context, dataControllable: dataControllable, itemController: itemController)
            syncDataController = controller
            syncTask = controller.start()
        }
    }

    private var _rootManager: RootManager?
    public var rootManager: RootManager {
        get { _rootManager! }
        set { _rootManager = newValue }
    }
    private(set) var context: NSManagedObjectContext?
    private(set) var batchContext: NSManagedObjectContext?
    private var _adventureRootControllable: (any RootExportControllable)?
    var adventureRootControllable: any RootExportControllable { _adventureRootControllable! }
    private var _linkRegisterController: LinkRegisterController?
    var linkRegisterController: LinkRegisterController { _linkRegisterController! }

    public let config: ModuleConfiguration
    let tagController: TagController
    let searchModel: SearchModel
    let listDisplayModel: ListDisplayModel

    @ObservationIgnored public var itemSelectionModel: ItemSelectionModel
    @MainActor public var navigationModel: ModuleNavigationModel
    @ObservationIgnored public var linkSelectionModel: ItemSelectionModel

    @MainActor public var currentSelectedItemId: UUID? { folderListController.listModel.selectedItemId }
    public let removeEntryListModel = RemoveEntryListModel()

    var cacheController: CacheController? { itemController.cacheController }
    public var fileUrlDataController: FileUrlDataController? { itemController.fileUrlDataController }

    @ObservationIgnored var syncDataController: SyncDataController?
    @ObservationIgnored var syncTask: Task<Void, Never>?

    let itemController: ItemController
    let sheetController: SheetController

    @ObservationIgnored private var _exportController: ExportController?
    var exportController: ExportController { _exportController! }
    @ObservationIgnored private var _gameController: GameController?
    var gameController: GameController { _gameController! }
    @ObservationIgnored private var _linkController: LinkController?
    var linkController: LinkController { _linkController! }
    @ObservationIgnored private var _editController: EditController?
    var editController: EditController { _editController! }
    @ObservationIgnored private var _importController: ImportController?
    var importController: ImportController {
        if let controller = _importController { return controller }
        let controller = ImportController(itemController: itemController, editController: editController)
        _importController = controller
        return controller
    }
    @ObservationIgnored private var _searchController: SearchController?
    var searchController: SearchController {
        if let controller = _searchController { return controller }
        let controller = SearchController(itemController: itemController)
        _searchController = controller
        return controller
    }

    @ObservationIgnored private var _folderListController: FolderListControllable?
    var folderListController: FolderListControllable {
        if let controller = _folderListController { return controller }
        let controller = FolderListController(listModel: FolderListModel(isSelectionMode: false, selection: [], navigationModel: navigationModel), listDisplayModel: listDisplayModel, itemControllable: itemController, searchRootControllable: SearchListController(searchController: searchController, searchModel: searchModel, listDisplayModel: listDisplayModel))
        _folderListController = controller
        return controller
    }

    @ObservationIgnored private var _folderLinkController: FolderListControllable?
    var folderLinkController: FolderListControllable {
        if let controller = _folderLinkController { return controller }
        let linkDisplayModel = listDisplayModel.newListDisplayModel
        let controller = FolderListController(listModel: FolderListModel(isSelectionMode: false, selection: [], navigationModel: navigationModel), listDisplayModel: linkDisplayModel, itemControllable: itemController, searchRootControllable: SearchLinkController(searchController: searchController, searchModel: searchModel.newSearchModel, listDisplayModel: linkDisplayModel))
        _folderLinkController = controller
        return controller
    }

    @ObservationIgnored public lazy var viewController: ViewController = {
        ViewController()
    }()

    @MainActor @ObservationIgnored private var _rootController: ItemRootController?
    @MainActor public var rootController: ItemRootController {
        if let controller = _rootController { return controller }
        let controller = ItemRootController(
            rootManager: rootManager,
            config: config,
            navigationModel: navigationModel,
            inspectorEditorLinkModel: editorLinkModel,
            openFileWindowModel: openFileWindowModel,
            itemSelectionModel: itemSelectionModel,
            removeEntryListModel: removeEntryListModel,
            cacheControllable: cacheController,
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
        _rootController = controller
        return controller
    }

    @MainActor @ObservationIgnored lazy var editorLinkModel: EditorLinkModel = {
        EditorLinkModel(
            rootManager: RootManager(anyRoot: self),
            folderListController: folderLinkController,
            firstRow: [],
            selection: .none
        )
    }()

    @MainActor @ObservationIgnored lazy public var openFileWindowModel: OpenFileWindowModel = { OpenFileWindowModel(windowId: NetworkModules.space.viewerWindowId, route: { DetailRoute.viewer($0) })
    }()
}

@MainActor
extension SpaceRootModel: ItemRootControllable {
    public var configurable: any ModuleConfigurable { config }
    public var cacheControllable: (any ImageCacheControllable)? { cacheController }
    public var editControllable: any EditControllable { editController }
    public var folderListControllable: any FolderListControllable { folderListController }
    public var folderLinkControllable: any FolderListControllable { folderLinkController }
    public var inspectorEditorLinkModel: EditorLinkModel? { editorLinkModel }
    public var sheetControllable: any SheetControllable { sheetController }
    public var viewControllable: any ViewControllable { viewController }
}

extension SpaceRootModel {
    public var exportControllable: any ExportControllable {
        exportController as ExportControllable
    }
    public var importControllable: any ImportControllable {
        importController as ImportControllable
    }
    public var gameControllable: any GameControllable {
        gameController
    }
    @MainActor public var itemControllable: any ItemControllable {
        itemController
    }
    public var searchControllable: any SearchControllable { searchController }

    public static let thumbnailSize: CGSize = .init(width: 64.0, height: 64.0)

    @MainActor
    public func listItems() -> [SpaceModel] {
        itemController.itemDataModel.items.map {
            itemController.itemOrEmpty(for: $0)
        }
    }

    public func itemDataCleanup() async throws {
        for itemId in itemController.itemDataModel.items {
            guard let model = await itemController.item(for: itemId) else { continue }
            if model.displayState == 2 {
                await editController.delete(itemId: model.id)
            }
        }
    }

    public func checkFolders(reportModel: ValidateRepairModel) async {
        let cc = ConvertController(itemController: itemController, editController: editController)
        await cc.repairHiddenAndFolders(reportModel: reportModel)
    }

    public func validateLinks(reportModel: ValidateRepairModel) async {
        await linkController.validateLinks(reportModel: reportModel)
    }
}
