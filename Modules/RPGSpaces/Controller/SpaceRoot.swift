// @copyright André Trettin

import AndrenalinKit
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
public final class SpaceRoot: @unchecked Sendable {
    public static let thumbnailSize: CGSize = .init(width: 64.0, height: 64.0)
    
    @MainActor
    init(context: NSManagedObjectContext?) {
        rootModel = RootModel()
        self.context = context
        let modelContainer = try! ModelContainer(for: TagDataModel.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        
        let module: NetworkModules = .space
        self.module = module
        
        let listDisplayModel = ListDisplayModel()
        self.listDisplayModel = listDisplayModel
        let searchModel = SearchModel(modelContainer: modelContainer, module: module, categoryTags: [.building, .item, .supplement])
        self.searchModel = searchModel
        
        let itemSelectionModel = ItemSelectionModel()
        self.itemSelectionModel = itemSelectionModel

        let fileController = FileController(root: self)
        let cacheController = CacheController(fileUrlDataController: fileController.fileUrlDataController)
        
        let dataController: DataController?
        if let context {
            dataController = DataController(context: context, token: NetworkModules.space.token)
        } else {
            dataController = nil
        }

        let itemController = ItemController(cacheController: cacheController, dataController: dataController, fileUrlDataController: fileController.fileUrlDataController, linkRegisterControllable: linkRegisterControllable)
            
        if let dataController, let context {
            let syncDataController = SyncDataController(context: context, dataController: dataController, itemController: itemController)
            _syncDataController = syncDataController
        }
        _cacheController = cacheController
        _dataController = dataController
        _fileController = fileController
        _itemController = itemController

        _editControllers = [EditTypes.main: EditController(root: self, fileUrlDataController: fileController.fileUrlDataController, currentListItem: nil, currentModel: nil)]
        _exportController = ExportController(root: self, gameExporter: false)
        _importController = ImportController(root: self, itemController: self.itemController)
        _gameController = GameController(root: self, itemController: self.itemController)
        _linkController = LinkController(root: self)
        _viewController = ViewController(root: self)
    }
    
    public let rootModel: RootModel
    private let context: NSManagedObjectContext?
    public let module: NetworkModules
    
    public let listDisplayModel: ListDisplayModel
    public let searchModel: SearchModel
    public var itemSelectionModel: ItemSelectionModel
    @MainActor
    public var currentSelectedItemId: UUID? {
        rootModel.selectedItem?.itemId
    }
    
    @ObservationIgnored private(set) var _cacheController: CacheController?
    var cacheController: CacheController {
        _cacheController.unsafelyUnwrapped
    }
    @ObservationIgnored private(set) var _dataController: DataController?
    var dataController: DataController? {
        _dataController
    }
    @ObservationIgnored private(set) var _syncDataController: SyncDataController?
    var syncDataController: SyncDataController? {
        _syncDataController
    }

    @ObservationIgnored
    private(set) var _fileController: FileController?
    var fileController: FileController {
        _fileController.unsafelyUnwrapped
    }
    
    public var fileUrlDataController: FileUrlDataController {
        fileController.fileUrlDataController
    }
    
    @ObservationIgnored
    private(set) var _itemController: ItemController?
    var itemController: ItemController {
        _itemController.unsafelyUnwrapped
    }
    
    @ObservationIgnored
    private var _editControllers: [EditTypes: EditController] = [:]

    @ObservationIgnored
    private(set) var _exportController: ExportController?
    var exportController: ExportController {
        _exportController.unsafelyUnwrapped
    }
    
    @ObservationIgnored
    private(set) var _importController: ImportController?
    var importController: ImportController {
        _importController.unsafelyUnwrapped
    }
    
    @ObservationIgnored
    private(set) var _gameController: GameController?
    var gameController: GameController {
        _gameController.unsafelyUnwrapped
    }
    
    @ObservationIgnored
    private(set) var _linkController: LinkController?
    public var linkController: LinkController {
        _linkController.unsafelyUnwrapped
    }
    
    @MainActor @ObservationIgnored lazy var folderListController: FolderListControllable = {
        FolderListController(listModel: FolderListModel(isSelectionMode: false, selection: []), listDisplayModel: listDisplayModel, searchModel: searchModel)
    }()

    @ObservationIgnored
    private(set) var _viewController: ViewController?
    public var viewController: ViewController {
        _viewController.unsafelyUnwrapped
    }
    
    @ObservationIgnored
    private(set) var _rootControllable: RootControllable?
    var rootControllable: RootControllable {
        _rootControllable.unsafelyUnwrapped
    }
    
    @ObservationIgnored
    private(set) var mainListController: ListController?
    
    @MainActor @ObservationIgnored public lazy var rootController: ItemRootController = {
        ItemRootController(
            module: module,
            listDisplayModel: listDisplayModel,
            searchModel: searchModel,
            itemSelectionModel: ItemSelectionModel(),
            removeEntryListModel: RemoveEntryListModel(),
            cacheControllable: cacheController,
            editControllable: editController(type: .main),
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

extension SpaceRoot {
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
    
    func applyToAllEditController(handler: @escaping @Sendable (EditController) async -> Void) async {
        for editController in _editControllers.values {
            await handler(editController)
        }
    }

    @MainActor
    func editController(for item: ItemRowTreeModel? = nil, type: EditTypes) -> EditController {
        guard let oldEditController = _editControllers[type] else {
            let model = item.map { itemController.itemOrEmpty(for: $0.model.itemId) }
            let newEditController = EditController(root: self, fileUrlDataController: fileController.fileUrlDataController, currentListItem: item, currentModel: model)
            _editControllers[type] = newEditController
            return newEditController
        }
        return oldEditController
    }

    @MainActor
    private var listController: ListController {
        ListController(itemController: itemController, listStoreName: "Space", hasChildren: true, searchToken: .all, categoryTags: itemController.itemDataModel.categoryTags)
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
    public func setRootControllable(_ rootControllable: RootControllable) {
        self._rootControllable = rootControllable
        Task {
            syncDataController?.start()
        }
    }
    
    @MainActor
    private func setMainListController(_ listController: ListController) {
        guard mainListController == nil else { return }
        mainListController = listController
    }

    public func moveFiles() async throws {
        try await fileController.moveFiles()
    }
    
    @MainActor
    public func listItems() -> [SpaceModel] {
        itemController.itemDataModel.items.map {
            itemController.itemOrEmpty(for: $0)
        }
    }
}
