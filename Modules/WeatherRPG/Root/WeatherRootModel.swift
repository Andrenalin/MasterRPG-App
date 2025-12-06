// @copyright André Trettin

import CoreRPG
import CoreData
import Foundation
import PhotoRPG
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
public final class WeatherRootModel: @unchecked Sendable {
    @MainActor init(container: ModelContainer, photoRoot: PhotoRootModel) {
        self.photoRoot = photoRoot
        
        rootModel = RootModel()
        let module: NetworkModules = .weather
        self.module = module
        
        let listDisplayModel = ListDisplayModel()
        self.listDisplayModel = listDisplayModel
        let searchModel = SearchModel(modelContainer: container, module: module, categoryTags: [.adventure, .map, .scenario])
        self.searchModel = searchModel
        
        self.itemSelectionModel = ItemSelectionModel()
        self.linkSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: true)
    }
    
    @MainActor public func setUp(context: NSManagedObjectContext?, rootControllable: RootControllable) {
        self._rootControllable = rootControllable

        let dataController = context.map { DataController(context: $0, token: module.token) }
        _dataController = dataController
        let itemController = ItemController(dataController: dataController, linkRegisterControllable: rootControllable.linkRegisterControllable)
        _itemController = itemController
        _editController = EditController(itemController: itemController, linkRegisterControllable: rootControllable.linkRegisterControllable, currentListItem: nil, currentModel: nil)
        _exportController = ExportController(photoRoot: photoRoot, itemController: itemController, gameExporter: false)
        _importController = ImportController(itemController: itemController)
        _gameController = GameController(photoRoot: photoRoot, itemController: itemController, linkRegisterControllable: rootControllable.linkRegisterControllable, rootExportControllable: rootControllable.gameExportControllable, rootImportControllable: rootControllable.gameImportControllable)
        _linkController = LinkController(photoRoot: photoRoot, itemController: itemController, gameController: gameController)

        if let dataController, let context {
            _syncDataController = SyncDataController(context: context, dataController: dataController, itemController: itemController)
            Task {
                syncDataController?.start()
            }
        }
    }
    
    let photoRoot: PhotoRootModel

    public let rootModel: RootModel
    public let module: NetworkModules
    
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
    @MainActor @ObservationIgnored lazy var folderLinkController: FolderListControllable = {
        folderListController.copy(parentModel: nil)
    }()
    @ObservationIgnored public lazy var viewController: ViewController = {
        ViewController()
    }()

    
    @ObservationIgnored private(set) var _rootControllable: RootControllable?
    var rootControllable: RootControllable { _rootControllable.unsafelyUnwrapped }
    
    @ObservationIgnored private(set) var mainListController: ListController?
    
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
            listControllable: listController,
            folderListControllable: folderListController,
            viewControllable: viewController
        )
    }()
}

extension WeatherRootModel: ItemRootControllable {
    public var cacheControllable: (any ImageCacheControllable)? { nil }
    public var editControllable: any EditControllable { editController }
    public var listControllable: any ListControllable { listController }
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
    
    @MainActor
    private var listController: ListController {
        ListController(itemController: itemController, listStoreName: "Weather", hasChildren: true, searchToken: .all, categoryTags: itemController.itemDataModel.categoryTags)
    }
    func listController(model: ListModel) -> ListController {
        ListController(itemController: itemController, itemListModel: model)
    }
    @MainActor
    func listController(tabId: UUID, focus: ItemRowModel? = nil) -> ListController {
        guard let listModel = rootModel.listModels[tabId] else {
            let newController = listController
            newController.update(models: itemController.itemDataModel.items.map { ItemRowModel(itemId: $0, typeId: itemController.itemDataModel.networkModule) })
            if let focus {
                newController.setFocusItem(model: focus)
            }
            setMainListController(newController)
            rootModel.listModels[tabId] = newController.model
            return newController
        }
        return listController(model: listModel)
    }
    
    @MainActor
    private func setMainListController(_ listController: ListController) {
        guard mainListController == nil else { return }
        mainListController = listController
    }
}

public extension WeatherRootModel {
    @MainActor
    func addNewWeather(name: String, text: String, photoId: UUID?) async {
        let itemRowModel = await itemController.addNew(type: nil)
        editController.setCurrentItem(to: ItemRowTreeModel(id: UUID(), model: itemRowModel))
        editController.model.name = name
        editController.model.description = text
        editController.model.photoId = photoId
        editController.save(with: String(localized: "Create new").localizedString)
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
                await itemController.delete(itemId: model.id)
            }
        }
    }
}
