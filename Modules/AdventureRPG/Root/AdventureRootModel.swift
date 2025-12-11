// @copyright André Trettin

import CoreRPG
import CoreData
import DiceRPG
import AudioRPG
import MapRPG
import PdfRPG
import PhotoRPG
import SpaceRPG
import TableRPG
import CharacterRPG
import SwiftData
import SwiftUI
import WeatherRPG

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
public final class AdventureRootModel: @unchecked Sendable {

    @MainActor
    init(container: ModelContainer, audioRoot: AudioRootModel, diceRoot: DiceRootModel, mapRoot: MapRootModel, pdfRoot: PdfRootModel, photoRoot: PhotoRootModel, spaceRoot: SpaceRootModel, tableRoot: TableRootModel, characterRoot: CharacterRootModel, weatherRoot: WeatherRootModel) {
        rootModel = RootModel()
        self.audioRoot = audioRoot
        self.diceRoot = diceRoot
        self.mapRoot = mapRoot
        self.pdfRoot = pdfRoot
        self.photoRoot = photoRoot
        self.spaceRoot = spaceRoot
        self.tableRoot = tableRoot
        self.characterRoot = characterRoot
        self.weatherRoot = weatherRoot

        let module: NetworkModules = .adventure
        self.module = module
        
        let listDisplayModel = ListDisplayModel()
        self.listDisplayModel = listDisplayModel
        let searchModel = SearchModel(modelContainer: container, module: module, categoryTags: [.adventure, .campaign, .scenario, .rules, .supplement])
        self.searchModel = searchModel
        
        self.itemSelectionModel = ItemSelectionModel()
        self.linkSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: true)
    }
    
    @MainActor public func setUp(context: NSManagedObjectContext?) {
        let dataController = context.map { DataController(context: $0, token: module.token) }
        _dataController = dataController
        let linkRegisterController = LinkRegisterController(root: self)

        let itemController = ItemController(root: self, dataController: dataController, linkRegisterControllable: linkRegisterController)
        _itemController = itemController
        _editController = EditController(root: self, itemController: itemController, linkRegisterControllable: linkRegisterController, currentListItem: nil, currentModel: nil)
        _exportController = ExportController(root: self, itemController: itemController, gameExporter: false)
        _importController = ImportController(root: self, itemController: itemController, gameImporter: false)
        _gameController = GameController(root: self, itemController: itemController, linkRegisterControllable: linkRegisterController)
        _linkController = LinkController(root: self, itemController: itemController)

        _linkRegisterController = linkRegisterController
        
        audioRoot.setUp(context: context, rootControllable: self)
        diceRoot.setUp(context: context, rootControllable: self)
        pdfRoot.setUp(context: context, rootControllable: self)
        photoRoot.setUp(context: context, rootControllable: self)
        spaceRoot.setUp(context: context, rootControllable: self)
        weatherRoot.setUp(context: context, rootControllable: self)
        tableRoot.setUp(context: context, rootControllable: self)
        characterRoot.setUp(context: context, rootControllable: self)
        mapRoot.setUp(context: context, rootControllable: self)

        if let dataController, let context {
            _syncDataController = SyncDataController(context: context, dataController: dataController, itemController: itemController)
            Task {
                syncDataController?.start()
            }
        }
    }

    let audioRoot: AudioRootModel
    let diceRoot: DiceRootModel
    let mapRoot: MapRootModel
    let pdfRoot: PdfRootModel
    let photoRoot: PhotoRootModel
    let spaceRoot: SpaceRootModel
    let tableRoot: TableRootModel
    let characterRoot: CharacterRootModel
    let weatherRoot: WeatherRootModel

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
    
    @ObservationIgnored private(set) var _linkRegisterController: LinkRegisterController?
    var linkRegisterController: LinkRegisterController { _linkRegisterController.unsafelyUnwrapped }
    
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

extension AdventureRootModel: ItemRootControllable {
    public var cacheControllable: (any ImageCacheControllable)? { nil }
    public var editControllable: any EditControllable { editController }
    public var listControllable: any ListControllable { listController }
    public var folderListControllable: any FolderListControllable { folderListController }
    public var folderLinkControllable: any FolderListControllable { folderLinkController }
    public var viewControllable: any ViewControllable { viewController }
}


extension AdventureRootModel {
    public var gameControllable: any GameControllable {
        gameController
    }
    public var adventureGameControllable: any (GameControllable & AdventureStoreGameable) {
        gameController
    }
    public var itemControllable: any ItemControllable {
        itemController
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

extension AdventureRootModel: RootControllable {
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

extension AdventureRootModel: StoreManiplable {
    public func resetData() async {
        await itemController.resetData()
        await audioRoot.itemControllable.resetData()
        await diceRoot.itemControllable.resetData()
        await mapRoot.itemControllable.resetData()
        await pdfRoot.itemControllable.resetData()
        await photoRoot.itemControllable.resetData()
        await spaceRoot.itemControllable.resetData()
        await tableRoot.itemControllable.resetData()
        await characterRoot.itemControllable.resetData()
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
            characterRoot.linkController.validateLinks()
            weatherRoot.linkController.validateLinks()
        }
    }
}

public extension AdventureRootModel {
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

public extension AdventureRootModel {
    @MainActor
    func addNewAdventure(name: String, text: String, photoIds: [UUID], photoLinks: [String]) async {
        let itemRowModel = await itemController.addNew(type: nil)
        let editController = editController
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
    
    func itemDataCleanup() async throws {
        for itemId in await itemController.itemDataModel.items {
            guard let model = await itemController.item(for: itemId) else { continue }
            if model.displayState == 2 {
                await itemController.delete(itemId: model.id)
            }
        }
    }
    
    func checkFolders() async {
        let cc = ConvertController(itemController: itemController, editController: editController)
        await cc.createFolderAndCollections()
    }
}
