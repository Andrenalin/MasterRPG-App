// @copyright André Trettin

import AVFoundation
import CoreRPG
import CoreData
import SwiftData
import SwiftUI

@MainActor @Observable
public final class AudioRootModel {
    @MainActor init(tagController: TagController) {
        self.tagController = tagController
        
        let config = ModuleConfiguration()
        self.config = config
        
        self.itemSelectionModel = ItemSelectionModel()
        self.navigationModel = ModuleNavigationModel()
        self.linkSelectionModel = config.linkSelectionModel

        let audioPlayerModel = AudioPlayerModel()
        self.audioPlayerModel = audioPlayerModel
    }
    
    @MainActor public func setUp(context: NSManagedObjectContext?, batchContext: NSManagedObjectContext?, rootManager: RootManager, linkRegisterController: LinkRegisterController) {
        
        let searchModel = SearchModel(tagController: tagController, module: config.module, categoryTags: config.categoryTags)
        let listDisplayModel = ListDisplayModel()

        let dataController = context.map { DataController(context: $0, batchContext: batchContext, token: config.module.token) }
        _dataController = dataController

        let itemController = ItemController(config: config, dataController: dataController, linkRegisterController: linkRegisterController)
        _itemController = itemController
        _editController = EditController(itemController: itemController, linkRegisterController: linkRegisterController, tagController: tagController)
        _exportController = ExportController(rootManager: rootManager, itemController: itemController)
        _importController = ImportController(itemController: itemController, editController: editController)

        let audioController = AudioController(itemController: itemController, model: audioPlayerModel)
        _audioController = audioController

        let gameController = GameController(rootManager: rootManager, itemController: itemController, audioController: audioController, exportController: exportController)
        _gameController = gameController

        _linkController = LinkController(rootManager: rootManager, itemController: itemController, audioController: audioController, gameController: gameController)
        let searchController = SearchController(itemController: itemController)
        _searchController = searchController

        _sheetController = SheetController(itemController: itemController)
        
        let folderListModel = FolderListModel(isSelectionMode: false, selection: [], navigationModel: navigationModel)
        
        _folderListController = FolderListController(listModel: folderListModel, listDisplayModel: listDisplayModel, itemControllable: itemController, searchRootControllable: SearchListController(searchController: searchController, searchModel: searchModel, listDisplayModel: listDisplayModel))

        let folderLinkModel = FolderListModel(isSelectionMode: false, selection: [], navigationModel: navigationModel)
        let linkDisplayModel = listDisplayModel.newListDisplayModel
        
        _folderLinkController = FolderListController(listModel: folderLinkModel, listDisplayModel: linkDisplayModel, itemControllable: itemController, searchRootControllable: SearchLinkController(searchController: searchController, searchModel: searchModel.newSearchModel, listDisplayModel: linkDisplayModel))

        _rootController = ItemRootController(
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
                syncDataController?.start()
            }
        }
    }
    
    @MainActor @ObservationIgnored lazy public var openFileWindowModel: OpenFileWindowModel = {
        OpenFileWindowModel()
    }()

    public let config: ModuleConfiguration
    let tagController: TagController
    
    @ObservationIgnored public var itemSelectionModel: ItemSelectionModel
    @MainActor public var navigationModel: ModuleNavigationModel
    @ObservationIgnored public var linkSelectionModel: ItemSelectionModel
    
    @MainActor public var currentSelectedItemId: UUID? { folderListController.listModel.selectedItemId }
    public let removeEntryListModel = RemoveEntryListModel()
    
    public let audioPlayerModel: AudioPlayerModel
    
    @ObservationIgnored private(set) var _audioController: AudioController?
    var audioController: AudioController { _audioController! }

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
    var folderListController: FolderListController { _folderListController! }

    @ObservationIgnored private(set) var _folderLinkController: FolderListController?
    var folderLinkController: FolderListController { _folderLinkController! }

    @ObservationIgnored public lazy var viewController: ViewController = {
        ViewController()
    }()

    @MainActor @ObservationIgnored private(set) var _rootController: ItemRootController?
    @MainActor public var rootController: ItemRootController { _rootController!}
    
    @MainActor @ObservationIgnored lazy var editorLinkModel: EditorLinkModel = {
        EditorLinkModel(
            rootManager: RootManager(anyRoot: self),
            folderListController: folderLinkController,
            firstRow: [],
            selection: .none
        )
    }()
}

@MainActor
extension AudioRootModel: ItemRootControllable {
    public var configurable: any ModuleConfigurable { config }
    public var cacheControllable: (any ImageCacheControllable)? { nil }
    public var editControllable: any EditControllable { editController }
    public var folderListControllable: any FolderListControllable { folderListController }
    public var folderLinkControllable: any FolderListControllable { folderLinkController }
    public var inspectorEditorLinkModel: EditorLinkModel? { editorLinkModel }
    public var sheetControllable: any SheetControllable { sheetController }
    public var viewControllable: any ViewControllable { viewController }
}

extension AudioRootModel {
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
    public var audioGameControllable: any (GameControllable & AudioGameStoreable) {
        gameController
    }
}

// MARK: - AudioPlayer

extension AudioRootModel {
    @MainActor
    public var audioCoordinatorPlayback: AudioListenerCoordinator? {
        audioController.prewarm()
        return audioController.model.coordinator
    }

    @MainActor
    public func listItems() -> [AudioModel] {
        itemController.itemDataModel.items.map {
            itemController.itemOrEmpty(for: $0)
        }
    }

    public func itemDataCleanup() async throws {
        for itemId in itemController.itemDataModel.items {
            guard let model = await itemController.item(for: itemId) else { continue }
            if model.displayState == 2 {
                editController.delete(itemId: model.id)
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
