// @copyright André Trettin

import AndrenalinKit
import CoreData
import DiceRPG
import AudioRPG
import PdfRPG
import PhotoRPG
import TableRPG
import CharacterRPG
import CoreData
import SwiftData
import SwiftUI

@MainActor @Observable
public final class RootModel: Sendable {
    
    @MainActor
    public var selectedItem: ItemRowModel?
    @MainActor
    public var gameItemSelection: ItemRowModel?
    @MainActor
    var toolBarModel = GameToolBarModel()
    
    @ObservationIgnored
    var listModels: [UUID: ListModel] = [:]
}

@Observable
public final class MapRootModel: @unchecked Sendable {
    
    @MainActor
    init(container: ModelContainer, audioRoot: AudioRootModel, diceRoot: DiceRootModel, pdfRoot: PdfRootModel, photoRoot: PhotoRootModel, tableRoot: TableRootModel, valueRoot: CharacterRootModel) {
        rootModel = RootModel()
        
        let module: NetworkModules = .map
        self.module = module
        
        let listDisplayModel = ListDisplayModel()
        self.listDisplayModel = listDisplayModel
        let searchModel = SearchModel(modelContainer: container, module: module, categoryTags: [.building, .item, .supplement])
        self.searchModel = searchModel
        
        let itemSelectionModel = ItemSelectionModel()
        self.itemSelectionModel = itemSelectionModel

        self.audioRoot = audioRoot
        self.diceRoot = diceRoot
        self.pdfRoot = pdfRoot
        self.photoRoot = photoRoot
        self.tableRoot = tableRoot
        self.valueRoot = valueRoot
    }
    
    @MainActor public func setUp(context: NSManagedObjectContext?, rootControllable: RootControllable) {
        self._rootControllable = rootControllable
        
        _cacheController = CacheController(root: self)
        if let context {
            dataController = DataController(root: self, context: context, token: NetworkModules.map.token)
        }
        _itemController = ItemController(root: self, dataController: dataController)
        _editControllers = [EditTypes.main: EditController(root: self, currentListItem: nil, currentModel: nil)]
        _exportController = ExportController(root: self, itemController: self.itemController, gameExporter: false)
        _importController = ImportController(root: self, itemController: self.itemController, gameImporter: false)
        _gameController = GameController(root: self, itemController: self.itemController)
        _linkController = LinkController(root: self, itemController: self.itemController)
        _viewController = ViewController(root: self)

        Task {
            dataController?.start()
        }
    }

    public let rootModel: RootModel
    public let module: NetworkModules
    
    public let listDisplayModel: ListDisplayModel
    public let searchModel: SearchModel
    public var itemSelectionModel: ItemSelectionModel
    @MainActor public var currentSelectedItemId: UUID? { rootModel.selectedItem?.itemId }
    public let removeEntryListModel = RemoveEntryListModel()
    
    let audioRoot: AudioRootModel
    let diceRoot: DiceRootModel
    let pdfRoot: PdfRootModel
    let photoRoot: PhotoRootModel
    let tableRoot: TableRootModel
    let valueRoot: CharacterRootModel
    
    @ObservationIgnored
    private(set) var _cacheController: CacheController?
    var cacheController: CacheController {
        _cacheController.unsafelyUnwrapped
    }
    
    @ObservationIgnored
    private(set) var dataController: DataController?
    
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
        FolderListController(listModel: FolderListModel(isSelectionMode: false, selection: []), listDisplayModel: listDisplayModel, searchModel: searchModel, itemControllable: itemController)
    }()
    @MainActor @ObservationIgnored lazy var folderLinkController: FolderListControllable = {
        folderListController.copy(parentModel: nil)
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
            cacheControllable: nil,
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

extension MapRootModel: ItemRootControllable {
    public var cacheControllable: (any ImageCacheControllable)? { nil }
    public var editControllable: any EditControllable { editController(type: .main) }
    public var listControllable: any ListControllable { listController }
    public var folderListControllable: any FolderListControllable { folderListController }
    public var folderLinkControllable: any FolderListControllable { folderLinkController }
    public var viewControllable: any ViewControllable { viewController }
}

extension MapRootModel {
    public var exportControllable: any ExportControllable {
        exportController as ExportControllable
    }
    
    public var importControllable: any ImportControllable {
        importController as ImportControllable
    }
    
    public var gameControllable: any GameControllable {
        gameController
    }
    public var mapGameControllable: any (GameControllable & MapGameStorable) {
        gameController
    }
    public var itemControllable: any ItemControllable {
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
            let newEditController = EditController(root: self, currentListItem: item, currentModel: model)
            _editControllers[type] = newEditController
            return newEditController
        }
        return oldEditController
    }

    @MainActor
    private var listController: ListController {
        ListController(itemController: itemController, listStoreName: "Maps", hasChildren: true, searchToken: .all, categoryTags: itemController.itemDataModel.categoryTags)
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

// MARK: - Actions

extension MapRootModel {
    @MainActor
    public var mapActions: MapActions {
        MapActions(quickMap: editController(type: .main).generateQuickMap(name:photoId:))
    }
}

public extension MapRootModel {
    @MainActor
    func addNewMap(name: String, text: String, photoId: UUID?) async {
        let itemRowModel = await itemController.addNew(type: nil)
        let editController = editController(type: .main)
        editController.setCurrentItem(to: ItemRowTreeModel(id: UUID(), model: itemRowModel))
        editController.model.name = name
        editController.model.description = text
        editController.model.photoId = photoId
        editController.save(with: String(localized: "Create new").localizedString)
    }

    @MainActor
    func sheet(for itemId: UUID, level: Int = 0) -> SheetModel {
        SheetController(root: self).sheet(for: itemId, level: level)
    }
    
    @MainActor
    func listItems() -> [MapModel] {
        itemController.itemDataModel.items.map {
            itemController.itemOrEmpty(for: $0)
        }
    }
}
