// @copyright André Trettin

import AndrenalinKit
import RPGDie
import RPGPdfs
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
public final class TableRoot: @unchecked Sendable {
    
    @MainActor
    init(container: ModelContainer, diceRoot: DiceRootModel, pdfRoot: PdfRoot) {
        rootModel = RootModel()
        
        let module: NetworkModules = .photo
        self.module = module
        
        let listDisplayModel = ListDisplayModel()
        self.listDisplayModel = listDisplayModel
        let searchModel = SearchModel(modelContainer: container, module: module, categoryTags: [.building, .item, .supplement])
        self.searchModel = searchModel
        
        let itemSelectionModel = ItemSelectionModel()
        self.itemSelectionModel = itemSelectionModel

        self.diceRoot = diceRoot
        self.pdfRoot = pdfRoot
    }
    
    @MainActor public func setUp(context: NSManagedObjectContext?, rootControllable: RootControllable) {
        self._rootControllable = rootControllable
        
        if let context {
            dataController = DataController(root: self, context: context, token: NetworkModules.table.token)
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
            
    let diceRoot: DiceRootModel
    let pdfRoot: PdfRoot
    
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
}

extension TableRoot {
    public var exportControllable: any ExportControllable {
        exportController as ExportControllable
    }
    public var importControllable: any ImportControllable {
        importController as ImportControllable
    }
    public var gameControllable: any (GameControllable & TableGameStorable) {
        gameController
    }
    public var itemControllable: any ItemControllable {
        itemController
    }
    @MainActor
    public func generatorControllable(for tableItem: ItemRowModel, parentItem: ItemRowModel, listControllable: ListControllable) -> GeneratorControllable {
        GeneratorController(root: self, rootItemId: tableItem.itemId, parentItem: parentItem, listControllable: listControllable)
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
        SheetController(root: self).sheet(for: itemId, level: level)
    }
    
    @MainActor
    public func listItems() -> [TableModel] {
        itemController.itemDataModel.items.map {
            itemController.itemOrEmpty(for: $0)
        }
    }
}
