// @copyright André Trettin

import AVFoundation
import CoreRPG
import CoreData
import SwiftData
import SwiftUI

@MainActor @Observable
public final class AudioRootModel {
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

        let audioPlayerModel = AudioPlayerModel()
        self.audioPlayerModel = audioPlayerModel
    }
    
    @MainActor public func setUp(context: NSManagedObjectContext?, batchContext: NSManagedObjectContext?, rootManager: RootManager, linkRegisterController: LinkRegisterController) {
        let dataController = context.map { DataController(context: $0, batchContext: batchContext, token: config.module.token) }
        _dataController = dataController

        let itemController = ItemController(config: config, dataController: dataController, linkRegisterController: linkRegisterController)
        _itemController = itemController
        _editController = EditController(itemController: itemController, linkRegisterController: linkRegisterController, tagController: searchModel.tagController)
        _exportController = ExportController(rootManager: rootManager, itemController: itemController)
        _importController = ImportController(itemController: itemController, editController: editController)

        let audioController = AudioController(itemController: itemController, model: audioPlayerModel)
        _audioController = audioController

        let gameController = GameController(rootManager: rootManager, itemController: itemController, audioController: audioController, exportController: exportController)
        _gameController = gameController

        _linkController = LinkController(rootManager: rootManager, itemController: itemController, audioController: audioController, gameController: gameController)
        _searchController = SearchController(itemController: itemController)
        
        _folderListController = FolderListController(listModel: FolderListModel(isSelectionMode: false, selection: [], navigationModel: navigationModel), listDisplayModel: listDisplayModel, searchModel: searchModel, itemControllable: itemController)

        _rootController = ItemRootController(
            config: config,
            listDisplayModel: listDisplayModel,
            searchModel: searchModel,
            navigationModel: navigationModel,
            inspectorEditorLinkModel: editorLinkModel,
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
            searchControllable: searchController,
            viewControllable: viewController
        )

        if let dataController, let context {
            _syncDataController = SyncDataController(context: context, dataController: dataController, editController: editController)
            Task {
                syncDataController?.start()
            }
        }
    }
    
    public let config: ModuleConfiguration
    
    public let listDisplayModel: ListDisplayModel
    public let searchModel: SearchModel
    public var itemSelectionModel: ItemSelectionModel
    @MainActor public var navigationModel: ModuleNavigationModel
    public var linkSelectionModel: ItemSelectionModel
    
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

    @ObservationIgnored private(set) var _folderListController: FolderListController?
    var folderListController: FolderListControllable { _folderListController! }

    @MainActor @ObservationIgnored var folderLinkController: FolderListControllable {
        rootController.folderLinkControllable
    }

    @ObservationIgnored public lazy var viewController: ViewController = {
        ViewController()
    }()

    @MainActor @ObservationIgnored private(set) var _rootController: ItemRootController?
    @MainActor public var rootController: ItemRootController { _rootController!}
    
    @MainActor @ObservationIgnored lazy var editorLinkModel: EditorLinkModel = {
        EditorLinkModel(
            rootManager: RootManager(anyRoot: self),
            folderListController: folderListController.copy(parentModel: nil),
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
        audioController.model.coordinator
    }

    @MainActor
    public func listItems() -> [AudioModel] {
        itemController.itemDataModel.items.map {
            itemController.itemOrEmpty(for: $0)
        }
    }

    public func moveFiles() async throws {
        //try await fileController.moveFiles()
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
}
