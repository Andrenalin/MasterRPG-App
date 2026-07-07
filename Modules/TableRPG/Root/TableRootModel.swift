// @copyright André Trettin

import CoreRPG
import CoreData
import DiceRPG
import PdfRPG
import SwiftData
import SwiftUI

@MainActor @Observable
public final class TableRootModel {
    @MainActor init(tagController: TagController, diceRoot: DiceRootModel, pdfRoot: PdfRootModel) {
        self.tagController = tagController

        self.diceRoot = diceRoot
        self.pdfRoot = pdfRoot

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
        let exportController = ExportController(diceRoot: diceRoot, itemController: itemController)
        self.exportController = exportController
        self.gameController = GameController(diceRoot: diceRoot, itemController: itemController, exportController: exportController)
        self.linkController = LinkController(diceRoot: diceRoot, itemController: itemController, gameController: gameController)
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

        exportController.hubControllable = adventureRootControllable
        _editController = EditController(rootManager: rootManager, diceRoot: diceRoot, itemController: itemController, linkController: linkController, sheetController: sheetController, tagController: searchModel.tagController)
        editorLinkModel.rootManager = rootManager
        editorLinkModel.folderListController = folderLinkController

        syncTask?.cancel()
        if let dataControllable = itemController.itemDataModel.dataController, let context {
            let controller = SyncDataController(context: context, dataControllable: dataControllable, itemController: itemController)
            syncDataController = controller
            syncTask = controller.start()
        }
    }

    let diceRoot: DiceRootModel
    let pdfRoot: PdfRootModel

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

    @MainActor @ObservationIgnored lazy var editorLinkModel: EditorLinkModel = {
        EditorLinkModel(
            folderListController: folderLinkController,
            diceSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false),
            pdfSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: true),
            tableSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: true),
            firstRow: [.dice, .pdf, .table],
            selection: .table
        )
    }()

    @MainActor @ObservationIgnored private let _openFileWindowModel: OpenFileWindowModel = OpenFileWindowModel(windowId: NetworkModules.table.viewerWindowId, canShow: true) { DetailRoute.viewer($0) }
    @MainActor public var openFileWindowModel: OpenFileWindowModel { _openFileWindowModel }

    @ObservationIgnored var syncDataController: SyncDataController?
    @ObservationIgnored var syncTask: Task<Void, Never>?

    let itemController: ItemController
    let sheetController: SheetController
    
    @ObservationIgnored var exportController: ExportController
    @ObservationIgnored var gameController: GameController
    @ObservationIgnored var linkController: LinkController
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
    @ObservationIgnored private let _viewController: ViewController = ViewController()
    public var viewController: ViewController { _viewController }

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
        _rootController = controller
        return controller
    }
}

@MainActor
extension TableRootModel: ItemRootControllable {
    public var configurable: any ModuleConfigurable { config }
    public var cacheControllable: (any ImageCacheControllable)? { nil }
    public var editControllable: any EditControllable { editController }
    public var folderListControllable: any FolderListControllable { folderListController }
    public var folderLinkControllable: any FolderListControllable { folderLinkController }
    public var inspectorEditorLinkModel: EditorLinkModel? { editorLinkModel }
    public var sheetControllable: any SheetControllable { sheetController }
    public var viewControllable: any ViewControllable { viewController }
}

extension TableRootModel {
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
    public var tableGameControllable: any (GameControllable & TableGameStorable) {
        gameController
    }
}

// Other

public extension TableRootModel {
    @MainActor
    func listItems() -> [TableModel] {
        itemController.itemDataModel.items.map {
            itemController.itemOrEmpty(for: $0)
        }
    }

    func itemDataCleanup() async throws {
        for itemId in itemController.itemDataModel.items {
            guard let model = await itemController.item(for: itemId) else { continue }
            if model.displayState == 2 {
                await editController.delete(itemId: model.id)
            }
        }
    }

    func checkFolders(reportModel: ValidateRepairModel) async {
        let cc = ConvertController(itemController: itemController, editController: editController)
        await cc.repairHiddenAndFolders(reportModel: reportModel)
    }

    func validateLinks(reportModel: ValidateRepairModel) async {
        await linkController.validateLinks(reportModel: reportModel)
    }
}
