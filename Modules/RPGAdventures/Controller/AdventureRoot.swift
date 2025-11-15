// @copyright André Trettin

import AndrenalinKit
import CoreData
import RPGDie
import RPGAudios
import RPGMaps
import RPGPdfs
import RPGPhotos
import RPGSpaces
import RPGTables
import RPGValues
import SwiftData
import SwiftUI
import RPGWeathers

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
public final class AdventureRoot: @unchecked Sendable {

    @MainActor
    init(container: ModelContainer, audioRoot: AudioRoot, diceRoot: DiceRoot, mapRoot: MapRoot, pdfRoot: PdfRoot, photoRoot: PhotoRoot, spaceRoot: SpaceRoot, tableRoot: TableRoot, valueRoot: ValueRoot, weatherRoot: WeatherRootModel) {
        rootModel = RootModel()
        self.audioRoot = audioRoot
        self.diceRoot = diceRoot
        self.mapRoot = mapRoot
        self.pdfRoot = pdfRoot
        self.photoRoot = photoRoot
        self.spaceRoot = spaceRoot
        self.tableRoot = tableRoot
        self.valueRoot = valueRoot
        self.weatherRoot = weatherRoot

        let module: NetworkModules = .adventure
        self.module = module
        
        let listDisplayModel = ListDisplayModel()
        self.listDisplayModel = listDisplayModel
        let searchModel = SearchModel(modelContainer: container, module: module, categoryTags: [.building, .item, .supplement])
        self.searchModel = searchModel
        
        let itemSelectionModel = ItemSelectionModel()
        self.itemSelectionModel = itemSelectionModel
    }
    
    @MainActor public func setUp(context: NSManagedObjectContext?) {
        if let context {
            dataController = DataController(root: self, context: context, token: NetworkModules.adventure.token)
        }
        _itemController = ItemController(root: self, dataController: dataController)
        _editControllers = [EditTypes.main: EditController(root: self, currentListItem: nil, currentModel: nil)]
        _exportController = ExportController(root: self, itemController: self.itemController, gameExporter: false)
        _importController = ImportController(root: self, itemController: self.itemController, gameImporter: false)
        _gameController = GameController(root: self, itemController: self.itemController)
        _linkController = LinkController(root: self, itemController: self.itemController)
        _linkRegisterController = LinkRegisterController(root: self)
        _viewController = ViewController(root: self)
        
        audioRoot.setUp(context: context, rootControllable: self)
        diceRoot.setUp(context: context, rootControllable: self)
        pdfRoot.setUp(context: context, rootControllable: self)
        photoRoot.setUp(context: context, rootControllable: self)
        spaceRoot.setUp(context: context, rootControllable: self)
        weatherRoot.setUp(context: context, rootControllable: self)
        tableRoot.setUp(context: context, rootControllable: self)
        valueRoot.setUp(context: context, rootControllable: self)
        mapRoot.setUp(context: context, rootControllable: self)
        
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

    let audioRoot: AudioRoot
    let diceRoot: DiceRoot
    let mapRoot: MapRoot
    let pdfRoot: PdfRoot
    let photoRoot: PhotoRoot
    let spaceRoot: SpaceRoot
    let tableRoot: TableRoot
    let valueRoot: ValueRoot
    let weatherRoot: WeatherRootModel

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
    private(set) var _linkRegisterController: LinkRegisterController?
    var linkRegisterController: LinkRegisterController {
        _linkRegisterController.unsafelyUnwrapped
    }
    
    @ObservationIgnored
    private(set) var _viewController: ViewController?
    public var viewController: ViewController {
        _viewController.unsafelyUnwrapped
    }
    
    @ObservationIgnored
    private(set) var mainListController: ListController?
}

extension AdventureRoot {
    public var gameControllable: any (GameControllable & AdventureStoreGameable) {
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
        ListController(itemController: itemController, listStoreName: "Adventures", hasChildren: true, searchToken: .all, categoryTags: itemController.itemDataModel.categoryTags)
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

extension AdventureRoot: RootControllable {
    public var exportControllable: any ExportControllable {
        exportController as ExportControllable
    }
    public var importControllable: any ImportControllable {
        importController as ImportControllable
    }
    public var linkControllable: any LinkControllable {
        linkController as LinkControllable
    }
    @MainActor public var linkRegisterControllable: LinkRegisterControllable {
        linkRegisterController
    }
    public var gameExportControllable: any ExportControllable {
        gameController.gameExportController as ExportControllable
    }
    public var gameImportControllable: any ImportControllable {
        gameController.importController as ImportControllable
    }
}

extension AdventureRoot: StoreManiplable {
    public func resetData() async {
        await itemController.resetData()
        await audioRoot.itemControllable.resetData()
        await diceRoot.itemControllable.resetData()
        await mapRoot.itemControllable.resetData()
        await pdfRoot.itemControllable.resetData()
        await photoRoot.itemControllable.resetData()
        await spaceRoot.itemControllable.resetData()
        await tableRoot.itemControllable.resetData()
        await valueRoot.itemControllable.resetData()
        await weatherRoot.itemControllable.resetData()
    }

    @Sendable
    public func save() async {
        await itemController.save()
    }

    public func validate() {
        Task { @MainActor in
            linkController.validateLinks()
            audioRoot.linkController.validateLinks()
            diceRoot.linkController.validateLinks()
            mapRoot.linkController.validateLinks()
            pdfRoot.linkController.validateLinks()
            photoRoot.linkController.validateLinks()
            spaceRoot.linkController.validateLinks()
            tableRoot.linkController.validateLinks()
            valueRoot.linkController.validateLinks()
            weatherRoot.linkController.validateLinks()
        }
    }
}

public extension AdventureRoot {
    @MainActor
    func networkTitle(for id: UUID) -> String {
        itemController.itemOrEmpty(for: id).name
    }

    @MainActor
    func titleImage(for id: UUID?) async -> AKImage? {
        guard let id else { return nil }
        let (image, _) = await photoRoot.fetchPhotoImage(for: itemController.itemOrEmpty(for: id).photoId, useGame: false) ?? (nil, 0.0)
        return image
    }
}

public extension AdventureRoot {
    @MainActor
    func addNewAdventure(name: String, text: String, photoIds: [UUID], photoLinks: [String]) async {
        let itemRowModel = await itemController.addNew(type: nil)
        let editController = editController(type: .main)
        editController.setCurrentItem(to: ItemRowTreeModel(id: UUID(), model: itemRowModel))
        editController.model.name = name
        editController.model.description = text
        editController.model.photoId = photoIds.first
        let entry = AdventureEntryModel(id: UUID(), name: String(localized: "Photos").localizedString, content: photoLinks.joined(separator: ", "))
        editController.model.entries = [entry]
        editController.save(with: String(localized: "Create new").localizedString)
    }
    
    @MainActor
    func listItems() -> [AdventureModel] {
        itemController.itemDataModel.items.map {
            itemController.itemOrEmpty(for: $0)
        }
    }
}
