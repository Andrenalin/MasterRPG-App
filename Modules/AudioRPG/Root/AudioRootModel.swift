// @copyright André Trettin

import CoreRPG
import AVFoundation
import CoreData
import SwiftData
import SwiftUI

@MainActor @Observable
public final class RootModel: Sendable {
    
    @MainActor
    public var selectedItem: ItemRowModel?
    @MainActor
    public var gameItemSelection: ItemRowModel?
    
    @ObservationIgnored
    var listModels: [UUID: ListModel] = [:]
}

@Observable
public final class AudioRootModel: @unchecked Sendable {
    @MainActor init(container: ModelContainer) {
        rootModel = RootModel()
        let module: NetworkModules = .audio
        self.module = module
        
        let listDisplayModel = ListDisplayModel()
        self.listDisplayModel = listDisplayModel
        let searchModel = SearchModel(modelContainer: container, module: module, categoryTags: [.music, .playlist, .sound])
        self.searchModel = searchModel
        
        self.itemSelectionModel = ItemSelectionModel()
        self.linkSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: true)

        let audioPlayerModel = AudioPlayerModel()
        self.audioPlayerModel = audioPlayerModel
    }
    
    @MainActor public func setUp(context: NSManagedObjectContext?, rootControllable: RootControllable) {
        self._rootControllable = rootControllable

        let dataController = context.map { DataController(context: $0, token: module.token) }
        _dataController = dataController

        let itemController = ItemController(dataController: dataController, linkRegisterControllable: rootControllable.linkRegisterControllable)
        _itemController = itemController
        _editController = EditController(itemController: itemController, linkRegisterControllable: rootControllable.linkRegisterControllable, currentListItem: nil, currentModel: nil)
        _exportController = ExportController(itemController: itemController, gameExporter: false)
        _importController = ImportController(itemController: itemController)

        let audioController = AudioController(itemController: itemController, model: audioPlayerModel)
        _audioController = audioController

        let gameController = GameController(itemController: itemController, audioController: audioController, linkRegisterControllable: rootControllable.linkRegisterControllable, rootExportControllable: rootControllable.gameExportControllable, rootImportControllable: rootControllable.gameImportControllable)
        _gameController = gameController

        _linkController = LinkController(itemController: itemController, audioController: audioController, gameController: gameController)

        if let dataController, let context {
            _syncDataController = SyncDataController(context: context, dataController: dataController, itemController: itemController)
            Task {
                syncDataController?.start()
            }
        }
    }
    
    public let rootModel: RootModel
    public let module: NetworkModules
    
    public let listDisplayModel: ListDisplayModel
    public let searchModel: SearchModel
    public var itemSelectionModel: ItemSelectionModel
    public var linkSelectionModel: ItemSelectionModel
    
    @MainActor public var currentSelectedItemId: UUID? { folderListController.listModel.selectedItemId }
    public let removeEntryListModel = RemoveEntryListModel()
    
    public let audioPlayerModel: AudioPlayerModel
    
    @ObservationIgnored private(set) var _audioController: AudioController?
    var audioController: AudioController { _audioController.unsafelyUnwrapped }
    
    @ObservationIgnored private(set) var _dataController: DataController?
    var dataController: DataController? { _dataController }
    public var fileUrlDataController: FileUrlDataController? { itemController.fileUrlDataController }
    @ObservationIgnored private(set) var _syncDataController: SyncDataController?
    var syncDataController: SyncDataController? { _syncDataController }
    
    @ObservationIgnored private(set) var _itemController: ItemController?
    var itemController: ItemController { _itemController.unsafelyUnwrapped }
    
    @ObservationIgnored private(set) var _editController: EditController?
    var editController: EditController { _editController.unsafelyUnwrapped }
    @ObservationIgnored private(set) var _exportController: ExportController?
    var exportController: ExportController { _exportController.unsafelyUnwrapped }
    @ObservationIgnored private(set) var _importController: ImportController?
    var importController: ImportController { _importController.unsafelyUnwrapped }
    @ObservationIgnored private(set) var _gameController: GameController?
    var gameController: GameController { _gameController.unsafelyUnwrapped }
    @ObservationIgnored private(set) var _linkController: LinkController?
    public var linkController: LinkController { _linkController.unsafelyUnwrapped }
    
    @MainActor @ObservationIgnored lazy var folderListController: FolderListControllable = {
        FolderListController(listModel: FolderListModel(isSelectionMode: false, selection: []), listDisplayModel: listDisplayModel, searchModel: searchModel, itemControllable: itemController)
    }()
    @MainActor @ObservationIgnored var folderLinkController: FolderListControllable {
        rootController.folderLinkControllable
    }

    @ObservationIgnored public lazy var viewController: ViewController = {
        ViewController()
    }()

    @ObservationIgnored private(set) var _rootControllable: RootControllable?
    var rootControllable: RootControllable { _rootControllable.unsafelyUnwrapped }
    
    @MainActor @ObservationIgnored public lazy var rootController: ItemRootController = {
        ItemRootController(
            module: module,
            listDisplayModel: listDisplayModel,
            searchModel: searchModel,
            itemSelectionModel: ItemSelectionModel(),
            removeEntryListModel: RemoveEntryListModel(),
            cacheControllable: nil,
            editControllable: editController,
            exportControllable: exportControllable,
            gameControllable: gameControllable,
            itemControllable: itemControllable,
            linkControllable: linkControllable,
            folderListControllable: folderListController,
            viewControllable: viewController
        )
    }()
}

extension AudioRootModel: ItemRootControllable {
    public var cacheControllable: (any ImageCacheControllable)? { nil }
    public var editControllable: any EditControllable { editController }
    public var folderListControllable: any FolderListControllable { folderListController }
    public var folderLinkControllable: any FolderListControllable { folderLinkController }
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
    public var audioGameControllable: any (GameControllable & AudioGameStoreable) {
        gameController
    }
    
    @MainActor public var itemControllable: any ItemControllable {
        itemController
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
        for itemId in await itemController.itemDataModel.items {
            guard let model = await itemController.item(for: itemId) else { continue }
            if model.displayState == 2 {
                await itemController.delete(itemId: model.id)
            }
        }
    }
    
    public func checkFolders() async {
        let cc = ConvertController(itemController: itemController, editController: editController)
        await cc.createFilepathFoldersAndCollections()
    }
}
