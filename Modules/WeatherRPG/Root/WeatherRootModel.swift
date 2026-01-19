// @copyright André Trettin

import CoreRPG
import CoreData
import Foundation
import PhotoRPG
import SwiftUI

@Observable
public final class WeatherRootModel: @unchecked Sendable {
    @MainActor init(tagController: TagController, photoRoot: PhotoRootModel) {
        self.photoRoot = photoRoot
        
        let config = ModuleConfiguration()
        self.config = config
        
        let listDisplayModel = ListDisplayModel()
        self.listDisplayModel = listDisplayModel
        let searchModel = SearchModel(tagController: tagController, module: config.module, categoryTags: config.categoryTags)
        self.searchModel = searchModel
        
        self.itemSelectionModel = ItemSelectionModel()
        self.linkSelectionModel = config.linkSelectionModel
    }
    
    @MainActor public func setUp(context: NSManagedObjectContext?, rootControllable: RootControllable, linkRegisterController: LinkRegisterController) {
        self._rootControllable = rootControllable

        let dataController = context.map { DataController(context: $0, token: config.module.token) }
        _dataController = dataController
        let itemController = ItemController(config: config, dataController: dataController, linkRegisterController: linkRegisterController)
        _itemController = itemController
        _editController = EditController(itemController: itemController, linkRegisterController: linkRegisterController, tagController: searchModel.tagController)
        _exportController = ExportController(photoRoot: photoRoot, itemController: itemController, gameExporter: false)
        _importController = ImportController(itemController: itemController)
        _gameController = GameController(config: config, photoRoot: photoRoot, itemController: itemController, linkRegisterController: linkRegisterController, rootExportControllable: rootControllable.gameExportControllable, rootImportControllable: rootControllable.gameImportControllable)
        _linkController = LinkController(photoRoot: photoRoot, itemController: itemController, gameController: gameController)

        if let dataController, let context {
            _syncDataController = SyncDataController(context: context, dataController: dataController, editController: editController)
            Task {
                syncDataController?.start()
            }
        }
    }
    
    let photoRoot: PhotoRootModel
    public let config: ModuleConfiguration
    
    public let listDisplayModel: ListDisplayModel
    public let searchModel: SearchModel
    public var itemSelectionModel: ItemSelectionModel
    public var linkSelectionModel: ItemSelectionModel
    
    @MainActor public var currentSelectedItemId: UUID? { folderListController.listModel.selectedItemId }
    public let removeEntryListModel = RemoveEntryListModel()
    
    @ObservationIgnored private(set) var _dataController: DataController?
    var dataController: DataController? { _dataController }
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
            config: config,
            listDisplayModel: listDisplayModel,
            searchModel: searchModel,
            itemSelectionModel: itemSelectionModel,
            removeEntryListModel: removeEntryListModel,
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

extension WeatherRootModel: ItemRootControllable {
    public var configurable: any ModuleConfigurable { config }
    public var cacheControllable: (any ImageCacheControllable)? { nil }
    public var editControllable: any EditControllable { editController }
    public var folderListControllable: any FolderListControllable { folderListController }
    public var folderLinkControllable: any FolderListControllable { folderLinkController }
    public var viewControllable: any ViewControllable { viewController }
}

extension WeatherRootModel {
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
}

public extension WeatherRootModel {
    @MainActor func addNewWeather(name: String, text: String, photoId: UUID?) async {
        let itemId = await itemController.addNew(type: .item)
        editController.reset(name: name, itemId: itemId)
        editController.reset(description: text, itemId: itemId)
        editController.add(photoId: photoId, itemId: itemId)
    }
    
    @MainActor
    func listItems() -> [WeatherModel] {
        itemController.itemDataModel.items.map {
            itemController.itemOrEmpty(for: $0)
        }
    }
    
    func itemDataCleanup() async throws {
        for itemId in await itemController.itemDataModel.items {
            guard let model = await itemController.item(for: itemId) else { continue }
            if model.displayState == 2 {
                await editController.delete(itemId: model.id)
            }
        }
    }
    
    func checkFolders() async {
        let cc = ConvertController(itemController: itemController, editController: editController)
        await cc.createFoldersAndCollections()
    }
}
