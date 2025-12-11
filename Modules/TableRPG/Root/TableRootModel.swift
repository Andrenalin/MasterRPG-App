// @copyright André Trettin

import CoreRPG
import CoreData
import DiceRPG
import PdfRPG
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

    @MainActor
    var generatorItemId: UUID = UUID()
    
    @MainActor
    private(set) var generatorController: GeneratorController?
    
    @MainActor
    func resetGeneratorController(rootItem: ItemRowModel?, generatorController: GeneratorController) {
        generatorItemId = rootItem?.itemId ?? UUID()
        self.generatorController = generatorController
    }
}

@Observable
public final class TableRootModel: @unchecked Sendable {
    @MainActor init(container: ModelContainer, diceRoot: DiceRootModel, pdfRoot: PdfRootModel) {
        self.diceRoot = diceRoot
        self.pdfRoot = pdfRoot

        rootModel = RootModel()
        let module: NetworkModules = .table
        self.module = module
        
        let listDisplayModel = ListDisplayModel()
        self.listDisplayModel = listDisplayModel
        let searchModel = SearchModel(modelContainer: container, module: module, categoryTags: [.rules, .loot, .supplement, .generator])
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
        _editController = EditController(diceRoot: diceRoot, itemController: itemController, linkRegisterControllable: rootControllable.linkRegisterControllable, currentListItem: nil, currentModel: nil)
        _exportController = ExportController(diceRoot: diceRoot, itemController: itemController, gameExporter: false)
        _importController = ImportController(itemController: itemController)
        _gameController = GameController(diceRoot: diceRoot, itemController: itemController, linkRegisterControllable: rootControllable.linkRegisterControllable, rootExportControllable: rootControllable.gameExportControllable, rootImportControllable: rootControllable.gameImportControllable)
        _linkController = LinkController(diceRoot: diceRoot, itemController: itemController, gameController: gameController)

        if let dataController, let context {
            _syncDataController = SyncDataController(context: context, dataController: dataController, itemController: itemController)
            Task {
                syncDataController?.start()
            }
        }
    }

    let diceRoot: DiceRootModel
    let pdfRoot: PdfRootModel

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

extension TableRootModel: ItemRootControllable {
    public var cacheControllable: (any ImageCacheControllable)? { nil }
    public var editControllable: any EditControllable { editController }
    public var listControllable: any ListControllable { listController }
    public var folderListControllable: any FolderListControllable { folderListController }
    public var folderLinkControllable: any FolderListControllable { folderLinkController }
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
    public var tableGameControllable: any (GameControllable & TableGameStorable) {
        gameController
    }
    @MainActor public var itemControllable: any ItemControllable {
        itemController
    }

    @MainActor
    public func generatorControllable(for tableItem: ItemRowModel, parentItem: ItemRowModel, listControllable: ListControllable) -> GeneratorControllable {
        GeneratorController(root: self, rootItemId: tableItem.itemId, parentItem: parentItem, listControllable: listControllable)
    }
    
    @MainActor
    private var listController: ListController {
        ListController(itemController: itemController, listStoreName: "Tables", hasChildren: true, searchToken: .all, categoryTags: itemController.itemDataModel.categoryTags)
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
    func generatorController(rootItem: ItemRowModel?) -> GeneratorController {
        GeneratorController(root: self, rootItemId: rootItem?.itemId ?? UUID())
    }
    
    @MainActor
    func resetGeneratorController(rootItem: ItemRowModel?) {
        rootModel.resetGeneratorController(rootItem: rootItem, generatorController: generatorController(rootItem: rootItem))
    }
    
    @MainActor
    private func setMainListController(_ listController: ListController) {
        guard mainListController == nil else { return }
        mainListController = listController
    }

    @MainActor
    public func sheet(for itemId: UUID, level: Int = 0) -> SheetModel {
        SheetController(itemController: itemController).sheet(for: itemId, level: level)
    }
    
    @MainActor
    public func listItems() -> [TableModel] {
        itemController.itemDataModel.items.map {
            itemController.itemOrEmpty(for: $0)
        }
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
        await cc.createFolderAndCollections()
    }
}
