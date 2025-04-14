// @copyright André Trettin

import AndrenalinKit
import RPGDie
import RPGPdfs
import RPGPhotos
import RPGTables
import CoreData
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
        let newRootId = rootItem?.itemId ?? UUID()
        if newRootId == generatorItemId {
            generatorItemId = UUID()
        }
        generatorItemId = newRootId
        self.generatorController = generatorController
    }
}

@Observable
public final class ValueRoot: @unchecked Sendable {

    @MainActor
    init(context: NSManagedObjectContext?, diceRoot: DiceRoot, pdfRoot: PdfRoot, photoRoot: PhotoRoot, tableRoot: TableRoot) {
        rootModel = RootModel()
        self.diceRoot = diceRoot
        self.pdfRoot = pdfRoot
        self.photoRoot = photoRoot
        self.tableRoot = tableRoot

        if let context {
            dataController = DataController(root: self, context: context, token: NetworkModules.value.token)
        }
        _itemController = ItemController(root: self, dataController: dataController)
        _editControllers = [EditTypes.main: EditController(root: self, currentListItem: nil, currentModel: nil)]
        _exportController = ExportController(root: self, itemController: self.itemController, gameExporter: false)
        _importController = ImportController(root: self, itemController: self.itemController, gameImporter: false)
        _gameController = GameController(root: self, itemController: self.itemController)
        _linkController = LinkController(root: self, itemController: self.itemController)
        _viewController = ViewController(root: self)
    }

    public let rootModel: RootModel
    
    let diceRoot: DiceRoot
    let pdfRoot: PdfRoot
    let photoRoot: PhotoRoot
    let tableRoot: TableRoot

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

extension ValueRoot {
    public var exportControllable: any ExportControllable {
        exportController as ExportControllable
    }
    public var importControllable: any ImportControllable {
        importController as ImportControllable
    }
    
    public var gameControllable: any (GameControllable & ValueGameStorable) {
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
        ListController(itemController: itemController, listStoreName: "Characters", hasChildren: true, searchToken: .all, categoryTags: itemController.itemDataModel.categoryTags)
    }
    func listController(model: ListModel) -> ListController {
        ListController(itemController: itemController, itemListModel: model)
    }
    @MainActor
    func listController(tabId: UUID, config: Bool = false, focus: ItemRowModel? = nil) -> ListController {
        guard let listModel = rootModel.listModels[tabId] else {
            let newController = listController
            if config {
                newController.model.categoryTags.removeAll(where: { $0 == .gameMaster })
                newController.model.hideChildrenHeader = true
            }
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
    func generatorController(rootItem: ItemRowModel?, saveId: UUID?) -> GeneratorController {
        GeneratorController(root: self, rootItemId: rootItem?.itemId ?? UUID(), saveId: saveId)
    }
    
    @MainActor
    func resetGeneratorController(rootItem: ItemRowModel?, saveId: UUID?) {
        rootModel.resetGeneratorController(rootItem: rootItem, generatorController: generatorController(rootItem: rootItem, saveId: saveId))
    }
    
    @MainActor
    public func setRootControllable(_ rootControllable: RootControllable) {
        self._rootControllable = rootControllable
        Task {
            dataController?.start()
        }
    }
    
    @MainActor
    private func setMainListController(_ listController: ListController) {
        guard mainListController == nil else { return }
        mainListController = listController
    }
}

// MARK: - Actions

extension ValueRoot {
    @MainActor
    public var valueActions: ValueActions {
        ValueActions(addResult: gameController.add(result:for:), createModelResult: gameController.create(name:description:entries:resultCategory:), createEntryResult: gameController.create(name:value:resultCategory:))
    }
}

public extension ValueRoot {
    @MainActor
    func addNewValue(name: String, text: String, photoIds: [UUID]) async {
        let itemRowModel = await itemController.addNew(type: nil)
        let editController = editController(type: .main)
        editController.setCurrentItem(to: ItemRowTreeModel(id: UUID(), model: itemRowModel))
        editController.model.name = name
        editController.model.description = text
        editController.model.photos = photoIds
        editController.model.photoId = photoIds.first
        editController.save(with: String(localized: "Create new").localizedString)
    }

    @MainActor
    func sheet(for itemId: UUID, level: Int = 0) -> SheetModel {
        SheetController(root: self).sheet(for: itemId, level: level)
    }
}
