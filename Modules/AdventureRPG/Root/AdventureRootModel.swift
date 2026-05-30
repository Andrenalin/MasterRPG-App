// @copyright André Trettin

import AudioRPG
import CharacterRPG
import CoreRPG
import CoreData
import DiceRPG
#if !os(tvOS)
import GeneratorRPG
#endif
import MapRPG
import PdfRPG
import PhotoRPG
import SpaceRPG
import SwiftUI
import TableRPG
import WeatherRPG

@MainActor @Observable
public final class AdventureRootModel {

    @MainActor
    init(tagController: TagController, audioRoot: AudioRootModel, diceRoot: DiceRootModel, generatorRoot: GeneratorRootModel?, mapRoot: MapRootModel, pdfRoot: PdfRootModel, photoRoot: PhotoRootModel, spaceRoot: SpaceRootModel, tableRoot: TableRootModel, characterRoot: CharacterRootModel, weatherRoot: WeatherRootModel) {
        self.audioRoot = audioRoot
        self.diceRoot = diceRoot
        self.generatorRoot = generatorRoot
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
        self.navigationModel = ModuleNavigationModel()
        self.linkSelectionModel = config.linkSelectionModel
    }
    
    @MainActor public func setUp(root: RootManager, context: NSManagedObjectContext?, batchContext: NSManagedObjectContext?) {
        self.rootManager = root
        
        let dataController = context.map { DataController(context: $0, token: config.module.token) }
        _dataController = dataController
        let linkRegisterController = LinkRegisterController(root: root)
        linkRegisterController.setup(context: context)

        let itemController = ItemController(config: config, dataController: dataController, linkRegisterController: linkRegisterController)
        _itemController = itemController
        _editController = EditController(root: self, itemController: itemController, linkRegisterController: linkRegisterController, tagController: searchModel.tagController)
        _exportController = ExportController(rootManager: root, itemController: itemController)
        _importController = ImportController(root: self, itemController: itemController)
        _gameController = GameController(rootManager: root, root: self, itemController: itemController, exportController: exportController)
        _linkController = LinkController(rootManager: root, itemController: itemController)
        _searchController = SearchController(itemController: itemController)
        _sheetController = SheetController(itemController: itemController, linkRegisterController: linkRegisterController)
        _linkRegisterController = linkRegisterController
        
        audioRoot.setUp(context: context, batchContext: batchContext, rootManager: root, linkRegisterController: linkRegisterController)
        diceRoot.setUp(context: context, batchContext: batchContext, rootManager: root, linkRegisterController: linkRegisterController)
        pdfRoot.setUp(context: context, batchContext: batchContext, rootManager: root, linkRegisterController: linkRegisterController)
        photoRoot.setUp(context: context, batchContext: batchContext, rootManager: root, linkRegisterController: linkRegisterController)
        spaceRoot.setUp(context: context, batchContext: batchContext, rootManager: root, linkRegisterController: linkRegisterController)
        weatherRoot.setUp(context: context, batchContext: batchContext, rootManager: root, linkRegisterController: linkRegisterController)
        tableRoot.setUp(context: context, batchContext: batchContext, rootManager: root, linkRegisterController: linkRegisterController)
        characterRoot.setUp(context: context, batchContext: batchContext, rootManager: root, linkRegisterController: linkRegisterController)
        mapRoot.setUp(context: context, batchContext: batchContext, rootManager: root, linkRegisterController: linkRegisterController)
#if !os(tvOS)
        generatorRoot?.setUp(context: context, batchContext: batchContext, rootManager: root, linkRegisterController: linkRegisterController)
#endif
        
        if let dataController, let context {
            _syncDataController = SyncDataController(context: context, dataController: dataController, editController: editController)
            Task {
                syncDataController?.start()
            }
        }
    }

    let audioRoot: AudioRootModel
    let diceRoot: DiceRootModel
    let generatorRoot: GeneratorRootModel?
    let mapRoot: MapRootModel
    let pdfRoot: PdfRootModel
    let photoRoot: PhotoRootModel
    let spaceRoot: SpaceRootModel
    let tableRoot: TableRootModel
    let characterRoot: CharacterRootModel
    let weatherRoot: WeatherRootModel

    var rootManager: RootManager?
    
    public let config: ModuleConfiguration
    
    public let listDisplayModel: ListDisplayModel
    let searchModel: SearchModel
    @ObservationIgnored public var itemSelectionModel: ItemSelectionModel
    @MainActor public var navigationModel: ModuleNavigationModel
    @ObservationIgnored public var linkSelectionModel: ItemSelectionModel
    
    @MainActor public var currentSelectedItemId: UUID? { folderListController.listModel.selectedItemId }
    public let removeEntryListModel = RemoveEntryListModel()
    
    @MainActor @ObservationIgnored lazy var editorLinkModel: EditorLinkModel = {
        EditorLinkModel(
            rootManager: rootManager!,
            folderListController: folderLinkController,
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
            rootManager: rootManager!,
            folderListController: folderLinkController,
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
    
    @MainActor @ObservationIgnored lazy public var openFileWindowModel: OpenFileWindowModel = { OpenFileWindowModel(windowId: NetworkModules.adventure.viewerWindowId, canShow: true) { DetailRoute.viewer($0) }
    }()

    @ObservationIgnored private(set) var _dataController: DataController?
    var dataController: DataController? { _dataController }
    @ObservationIgnored private(set) var _syncDataController: SyncDataController?
    var syncDataController: SyncDataController? { _syncDataController }
    
    @ObservationIgnored private(set) var _itemController: ItemController?
    var itemController: ItemController { _itemController! }
    
    @ObservationIgnored private(set) var _editController: EditController?
    var editController: EditController { _editController! }
    @ObservationIgnored private(set) var _exportController: ExportController?
    var exportController: ExportController { _exportController! }
    @ObservationIgnored private(set) var _importController: ImportController?
    var importController: ImportController { _importController! }
    @ObservationIgnored private(set) var _gameController: GameController?
    var gameController: GameController { _gameController! }
    @ObservationIgnored private(set) var _linkController: LinkController?
    var linkController: LinkController { _linkController! }
    @ObservationIgnored private(set) var _searchController: SearchController?
    var searchController: SearchController { _searchController! }
    @ObservationIgnored private(set) var _sheetController: SheetController?
    var sheetController: SheetController { _sheetController! }

    @ObservationIgnored private(set) var _linkRegisterController: LinkRegisterController?
    var linkRegisterController: LinkRegisterController { _linkRegisterController! }
    
    @MainActor @ObservationIgnored lazy var folderListController: FolderListControllable = {
        FolderListController(listModel: FolderListModel(isSelectionMode: false, selection: [], navigationModel: navigationModel), listDisplayModel: ListDisplayModel(displayMode: .compact), itemControllable: itemController, searchRootControllable: SearchListController(searchController: searchController, searchModel: searchModel))
    }()
    @MainActor @ObservationIgnored lazy var folderLinkController: FolderListControllable = {
        FolderListController(listModel: FolderListModel(isSelectionMode: false, selection: [], navigationModel: navigationModel), listDisplayModel: ListDisplayModel(displayMode: .compact), itemControllable: itemController, searchRootControllable: SearchLinkController(searchController: searchController, searchModel: searchModel.newSearchModel))
    }()
    @ObservationIgnored public lazy var viewController: ViewController = {
        ViewController()
    }()

    @MainActor @ObservationIgnored public lazy var rootController: ItemRootController = {
        ItemRootController(
            config: config,
            listDisplayModel: listDisplayModel,
            navigationModel: navigationModel,
            inspectorEditorLinkModel: editorLinkModel,
            openFileWindowModel: openFileWindowModel,
            itemSelectionModel: itemSelectionModel,
            removeEntryListModel: removeEntryListModel,
            cacheControllable: nil,
            editControllable: editController,
            exportControllable: exportControllable,
            gameControllable: gameControllable,
            importControllable: importControllable,
            itemControllable: itemControllable,
            linkControllable: linkControllable,
            folderListControllable: folderListController,
            folderLinkControllable: folderLinkControllable,
            searchControllable: searchController,
            sheetControllable: sheetController,
            viewControllable: viewController
        )
    }()
}

@MainActor
extension AdventureRootModel: ItemRootControllable {
    public var configurable: any ModuleConfigurable { config }
    public var cacheControllable: (any ImageCacheControllable)? { nil }
    public var editControllable: any EditControllable { editController }
    public var folderListControllable: any FolderListControllable { folderListController }
    public var folderLinkControllable: any FolderListControllable { folderLinkController }
    public var inspectorEditorLinkModel: EditorLinkModel? { editorLinkModel }
    public var sheetControllable: any SheetControllable { sheetController }
    public var viewControllable: any ViewControllable { viewController }
}

@MainActor
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
    public var searchControllable: any SearchControllable {
        searchController
    }
    public var gameImportControllable: any ImportControllable {
        importController as ImportControllable
    }
    public var gameExportControllable: any ExportControllable {
        exportController
    }
}

@MainActor
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
        await linkRegisterController.resetData()
        await searchModel.tagController.resetData()
    }

    @Sendable public func save() async {
        // Flush all module pending operations into the shared context without saving yet.
        await audioRoot.itemControllable.flushPendingOperations()
        await diceRoot.itemControllable.flushPendingOperations()
        #if !os(tvOS)
        await generatorRoot?.itemControllable.flushPendingOperations()
        #endif
        await mapRoot.itemControllable.flushPendingOperations()
        await pdfRoot.itemControllable.flushPendingOperations()
        await photoRoot.itemControllable.flushPendingOperations()
        await spaceRoot.itemControllable.flushPendingOperations()
        await tableRoot.itemControllable.flushPendingOperations()
        await characterRoot.itemControllable.flushPendingOperations()
        await weatherRoot.itemControllable.flushPendingOperations()
        await linkRegisterController.savePendingLinks()
        await searchModel.tagController.savePendingTags()
        // One context.save() covers all flushed changes from every module above.
        await itemController.save()
    }

    public func validate() {
        Task { @MainActor in
            let report = ValidateRepairModel()

            report.update(phase: .repairFolders)
            await checkFolders(reportModel: report)
            await audioRoot.checkFolders(reportModel: report)
            await diceRoot.checkFolders(reportModel: report)
            await mapRoot.checkFolders(reportModel: report)
            await pdfRoot.checkFolders(reportModel: report)
            await photoRoot.checkFolders(reportModel: report)
            await spaceRoot.checkFolders(reportModel: report)
            await tableRoot.checkFolders(reportModel: report)
            await characterRoot.checkFolders(reportModel: report)
            await weatherRoot.checkFolders(reportModel: report)

            report.update(phase: .validateLinks)
            await validateLinks(reportModel: report)
            await audioRoot.validateLinks(reportModel: report)
            await diceRoot.validateLinks(reportModel: report)
            await mapRoot.validateLinks(reportModel: report)
            await pdfRoot.validateLinks(reportModel: report)
            await photoRoot.validateLinks(reportModel: report)
            await spaceRoot.validateLinks(reportModel: report)
            await tableRoot.validateLinks(reportModel: report)
            await characterRoot.validateLinks(reportModel: report)
            await weatherRoot.validateLinks(reportModel: report)
        }
    }
}

// MARK: - Game

public extension AdventureRootModel {
    @MainActor func startGame() {
        itemController.itemDataModel.isGameMode = true
        audioRoot.itemControllable.itemDataModel.isGameMode = true
        diceRoot.itemControllable.itemDataModel.isGameMode = true
        mapRoot.itemControllable.itemDataModel.isGameMode = true
        pdfRoot.itemControllable.itemDataModel.isGameMode = true
        photoRoot.itemControllable.itemDataModel.isGameMode = true
        spaceRoot.itemControllable.itemDataModel.isGameMode = true
        tableRoot.itemControllable.itemDataModel.isGameMode = true
        characterRoot.itemControllable.itemDataModel.isGameMode = true
        weatherRoot.itemControllable.itemDataModel.isGameMode = true
    }
    
    @MainActor func networkTitle(for id: UUID) -> String {
        itemController.itemOrEmpty(for: id).name
    }

    @MainActor func titleImage(for id: UUID?) async -> AKImage? {
        guard let id else { return nil }
        let (image, _) = await photoRoot.fetchPhotoImage(for: itemController.itemOrEmpty(for: id).photoId, useGame: false) ?? (nil, 0.0)
        return image
    }
}

public extension AdventureRootModel {
    @MainActor
    func listItems() -> [AdventureModel] {
        itemController.itemDataModel.items.map {
            itemController.itemOrEmpty(for: $0)
        }
    }
    
    func itemDataCleanup() async throws {
        for itemId in itemController.itemDataModel.items {
            guard let model = await itemController.item(for: itemId) else { continue }
            if model.displayState == 2 {
                editController.delete(itemId: model.id)
            }
        }
    }
    
    func checkFolders(reportModel: ValidateRepairModel) async {
        let cc = ConvertController(itemController: itemController, editController: editController)
        await cc.repairHiddenAndFolders(reportModel: reportModel)
    }

    func validateLinks(reportModel: ValidateRepairModel) async {
        await linkController.validateLinks(reportModel: reportModel)
    }
}
