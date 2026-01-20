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

@Observable
public final class AdventureRootModel: @unchecked Sendable {

    @MainActor
    init(tagController: TagController, audioRoot: AudioRootModel, diceRoot: DiceRootModel, mapRoot: MapRootModel, pdfRoot: PdfRootModel, photoRoot: PhotoRootModel, spaceRoot: SpaceRootModel, tableRoot: TableRootModel, characterRoot: CharacterRootModel, weatherRoot: WeatherRootModel) {
        self.audioRoot = audioRoot
        self.diceRoot = diceRoot
        self.mapRoot = mapRoot
        self.pdfRoot = pdfRoot
        self.photoRoot = photoRoot
        self.spaceRoot = spaceRoot
        self.tableRoot = tableRoot
        self.characterRoot = characterRoot
        self.weatherRoot = weatherRoot

        let config = ModuleConfiguration()
        self.config = config
        
        let listDisplayModel = ListDisplayModel()
        self.listDisplayModel = listDisplayModel
        let searchModel = SearchModel(tagController: tagController, module: config.module, categoryTags: config.categoryTags)
        self.searchModel = searchModel
        
        self.itemSelectionModel = ItemSelectionModel()
        self.linkSelectionModel = config.linkSelectionModel
    }
    
    @MainActor public func setUp(root: RootManager, context: NSManagedObjectContext?) {
        let dataController = context.map { DataController(context: $0, token: config.module.token) }
        _dataController = dataController
        let linkRegisterController = LinkRegisterController(root: root)
        linkRegisterController.setup(context: context)

        let itemController = ItemController(config: config, dataController: dataController, linkRegisterController: linkRegisterController)
        _itemController = itemController
        _editController = EditController(root: self, itemController: itemController, linkRegisterController: linkRegisterController, tagController: searchModel.tagController)
        _exportController = ExportController(root: self, itemController: itemController, gameExporter: false)
        _importController = ImportController(root: self, itemController: itemController, gameImporter: false)
        _gameController = GameController(root: self, itemController: itemController, linkRegisterController: linkRegisterController)
        _linkController = LinkController(root: self, itemController: itemController)

        _linkRegisterController = linkRegisterController
        
        audioRoot.setUp(context: context, rootControllable: self, linkRegisterController: linkRegisterController)
        diceRoot.setUp(context: context, rootControllable: self, linkRegisterController: linkRegisterController)
        pdfRoot.setUp(context: context, rootControllable: self, linkRegisterController: linkRegisterController)
        photoRoot.setUp(context: context, rootControllable: self, linkRegisterController: linkRegisterController)
        spaceRoot.setUp(context: context, rootControllable: self, linkRegisterController: linkRegisterController)
        weatherRoot.setUp(context: context, rootControllable: self, linkRegisterController: linkRegisterController)
        tableRoot.setUp(context: context, rootControllable: self, linkRegisterController: linkRegisterController)
        characterRoot.setUp(context: context, rootControllable: self, linkRegisterController: linkRegisterController)
        mapRoot.setUp(context: context, rootControllable: self, linkRegisterController: linkRegisterController)

        if let dataController, let context {
            _syncDataController = SyncDataController(context: context, dataController: dataController, editController: editController)
            syncDataController?.start()
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

    public let config: ModuleConfiguration
    
    public let listDisplayModel: ListDisplayModel
    public let searchModel: SearchModel
    public var itemSelectionModel: ItemSelectionModel
    public var linkSelectionModel: ItemSelectionModel
    
    @MainActor public var currentSelectedItemId: UUID? { folderListController.listModel.selectedItemId }
    public let removeEntryListModel = RemoveEntryListModel()
    
    @MainActor @ObservationIgnored lazy var editorLinkModel: EditorLinkModel = {
        EditorLinkModel(
            rootManager: RootManager(adventureRoot: self, audioRoot: audioRoot, characterRoot: characterRoot, diceRoot: diceRoot, generatorRoot: self, mapRoot: mapRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, spaceRoot: spaceRoot, tableRoot: tableRoot, weatherRoot: weatherRoot),
            folderListController: folderListController.copy(parentModel: nil),
            adventureSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: true),
            audioSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false),
            characterSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false),
            diceSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false),
            mapSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: true),
            pdfSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: true),
            photoSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false),
            spaceSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false),
            tableSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: true),
            weatherSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false),
            firstRow: [.adventure, .map, .value, .table, .weather],
            secondRow: [.audio, .dice, .pdf, .photo, .space],
            selection: .map
        )
    }()

    @MainActor @ObservationIgnored lazy var playerLinkModel: EditorLinkModel = {
        EditorLinkModel(
            rootManager: RootManager(adventureRoot: self, audioRoot: audioRoot, characterRoot: characterRoot, diceRoot: diceRoot, generatorRoot: self, mapRoot: mapRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, spaceRoot: spaceRoot, tableRoot: tableRoot, weatherRoot: weatherRoot),
            folderListController: folderListController.copy(parentModel: nil),
            audioSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false),
            characterSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false),
            diceSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false),
            pdfSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false),
            photoSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false),
            spaceSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false),
            tableSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: true),
            firstRow: [.table, .pdf, .audio, .photo, .space, .dice],
            secondRow: [],
            selection: .table
        )
    }()

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

extension AdventureRootModel: ItemRootControllable {
    public var configurable: any ModuleConfigurable { config }
    public var cacheControllable: (any ImageCacheControllable)? { nil }
    public var editControllable: any EditControllable { editController }
    public var folderListControllable: any FolderListControllable { folderListController }
    public var folderLinkControllable: any FolderListControllable { folderLinkController }
    public var viewControllable: any ViewControllable { viewController }
}

extension AdventureRootModel: RootControllable {
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
    public var adventureGameControllable: any (GameControllable & AdventureStoreGameable) {
        gameController
    }

    public var linkControllable: any LinkControllable {
        linkController as LinkControllable
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
        let itemId = await itemController.addNew(type: .item)
        let editController = editController
        editController.reset(name: name, itemId: itemId)
        editController.reset(description: text, itemId: itemId)
        editController.add(photoId: photoIds.first, itemId: itemId)
        let entry = AdventureEntryModel(id: UUID(), name: String(localized: "Photos").localizedString, content: photoLinks.joined(separator: ", "))
        editController.add(entry: entry, itemId: itemId)
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
                await editController.delete(itemId: model.id)
            }
        }
    }
    
    func checkFolders() async {
        let cc = ConvertController(itemController: itemController, editController: editController)
        await cc.createFoldersAndCollections()
    }
}
