// @copyright André Trettin

import CoreRPG
import Foundation
import CoreData
import SwiftData

@MainActor @Observable
public final class GeneratorRootModel {
    @MainActor init(tagController: TagController) {
        let config = ModuleConfiguration()
        self.config = config
        
        let listDisplayModel = ListDisplayModel()
        self.listDisplayModel = listDisplayModel
        let searchModel = SearchModel(tagController: tagController, module: config.module, categoryTags: config.categoryTags)
        self.searchModel = searchModel
        
        self.itemSelectionModel = ItemSelectionModel()
        self.navigationModel = ModuleNavigationModel()
        self.linkSelectionModel = config.linkSelectionModel
    }
    
    @MainActor public func setUp(context: NSManagedObjectContext?, batchContext: NSManagedObjectContext?, rootManager: RootManager, adventureRootControllable: any RootControllable, linkRegisterController: LinkRegisterController) {
        self.rootManager = rootManager

        let dataController = context.map { DataController(context: $0, batchContext: batchContext, token: config.module.token) }
        _dataController = dataController
        let itemController = ItemController(config: config, dataController: dataController, linkRegisterController: linkRegisterController)
        _itemController = itemController

        _exportController = ExportController(rootController: adventureRootControllable, itemController: itemController)
        _gameController = GameController(itemController: itemController, exportController: exportController)
        _linkController = LinkController(itemController: itemController, gameController: gameController)
        _sheetController = SheetController(itemController: itemController)

        _editController = EditController(rootManager: rootManager, itemController: itemController, linkController: linkController, sheetController: sheetController, linkRegisterController: linkRegisterController, tagController: searchModel.tagController)
        
        _importController = ImportController(itemController: itemController, editController: editController)
        let searchController = SearchController(itemController: itemController)
        _searchController = searchController
        
        _folderListController = FolderListController(listModel: FolderListModel(isSelectionMode: false, selection: [], navigationModel: navigationModel), listDisplayModel: listDisplayModel, itemControllable: itemController, searchRootControllable: SearchListController(searchController: searchController, searchModel: searchModel, listDisplayModel: listDisplayModel))

        _folderLinkController = FolderListController(listModel: FolderListModel(isSelectionMode: false, selection: [], navigationModel: navigationModel), listDisplayModel: listDisplayModel.newListDisplayModel, itemControllable: itemController, searchRootControllable: SearchLinkController(searchController: searchController, searchModel: searchModel.newSearchModel, listDisplayModel: listDisplayModel.newListDisplayModel))

        _rootController = ItemRootController(
            rootManager: rootManager,
            config: config,
            navigationModel: navigationModel,
            inspectorEditorLinkModel: editorLinkModel,
            openFileWindowModel: openFileWindowModel,
            itemSelectionModel: itemSelectionModel,
            removeEntryListModel: removeEntryListModel,
            cacheControllable: nil,
            editControllable: editController,
            exportControllable: exportControllable,
            gameControllable: gameControllable,
            importControllable: importControllable,
            itemControllable: itemControllable,
            linkControllable: linkControllable,
            folderListControllable: folderListController,
            folderLinkControllable: folderLinkControllable,
            searchControllable: searchController,
            sheetControllable: sheetController,
            viewControllable: viewController
        )

        if let dataController, let context {
            _syncDataController = SyncDataController(context: context, dataController: dataController, editController: editController)
            Task {
                Task {
                syncDataController?.start()
            }
            }
        }
    }
    
    private var _rootManager: RootManager?
    public var rootManager: RootManager {
        get { _rootManager! }
        set { _rootManager = newValue }
    }

    public let config: ModuleConfiguration

    public let listDisplayModel: ListDisplayModel
    let searchModel: SearchModel
    public let itemSelectionModel: ItemSelectionModel
    @MainActor public var navigationModel: ModuleNavigationModel
    public let linkSelectionModel: ItemSelectionModel

    @MainActor public var currentSelectedItemId: UUID? { folderListController.listModel.selectedItemId }
    public let removeEntryListModel = RemoveEntryListModel()
    
    @ObservationIgnored private(set) var _dataController: DataController?
    var dataController: DataController? { _dataController }
    public var fileUrlDataController: FileUrlDataController? { itemController.fileUrlDataController }
    @ObservationIgnored private(set) var _syncDataController: SyncDataController?
    var syncDataController: SyncDataController? { _syncDataController }
    
    @ObservationIgnored private(set) var _itemController: ItemController?
    var itemController: ItemController { _itemController! }
    
    @ObservationIgnored private(set) var _editController: EditController?
    var editController: EditController { _editController! }
    @ObservationIgnored private(set) var _exportController: ExportController?
    var exportController: ExportController { _exportController! }
    @ObservationIgnored private(set) var _importController: ImportController?
    var importController: ImportController { _importController! }
    @ObservationIgnored private(set) var _gameController: GameController?
    var gameController: GameController { _gameController! }
    @ObservationIgnored private(set) var _linkController: LinkController?
    var linkController: LinkController { _linkController! }
    @ObservationIgnored private(set) var _searchController: SearchController?
    var searchController: SearchController { _searchController! }
    @ObservationIgnored private(set) var _sheetController: SheetController?
    var sheetController: SheetController { _sheetController! }

    @ObservationIgnored private(set) var _folderListController: FolderListController?
    var folderListController: FolderListControllable { _folderListController! }
    @ObservationIgnored private(set) var _folderLinkController: FolderListController?
    var folderLinkController: FolderListControllable { _folderLinkController! }

    @ObservationIgnored public lazy var viewController: ViewController = {
        ViewController()
    }()
    
    @ObservationIgnored private(set) var _rootControllable: RootControllable?
    var rootControllable: RootControllable { _rootControllable! }
    
    @MainActor @ObservationIgnored private(set) var _rootController: ItemRootController?
    @MainActor public var rootController: ItemRootController { _rootController!}
    
    @MainActor @ObservationIgnored lazy var generatorController: GeneratorController = {
        GeneratorController()
    }()
    
    @MainActor @ObservationIgnored lazy var adventureGeneratorController: AdventureGeneratorController = {
        AdventureGeneratorController()
    }()
    
    @MainActor @ObservationIgnored lazy var editorLinkModel: EditorLinkModel = {
        EditorLinkModel(
            rootManager: RootManager(anyRoot: self),
            folderListController: folderLinkController,
            firstRow: [],
            selection: .none
        )
    }()
    
    @MainActor @ObservationIgnored lazy public var openFileWindowModel: OpenFileWindowModel = {
        OpenFileWindowModel()
    }()
}

@MainActor
extension GeneratorRootModel: ItemRootControllable {
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
