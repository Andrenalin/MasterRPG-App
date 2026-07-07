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

        let itemController = ItemController(config: config)
        self.itemController = itemController
        self.sheetController = SheetController(itemController: itemController)
    }

    @MainActor public func setUp(root: RootManager, context: NSManagedObjectContext?, batchContext: NSManagedObjectContext?) {
        self.rootManager = root
        self.context = context

        let linkRegisterController = LinkRegisterController(root: root)
        linkRegisterController.setup(context: context)
        _linkRegisterController = linkRegisterController

        _importController = nil
        _searchController = nil
        _folderListController = nil
        _folderLinkController = nil
        _rootController = nil

        itemController.itemDataModel.dataController = context.map { DataController(context: $0, token: config.module.token) }
        itemController.itemDataModel.linkRegisterController = linkRegisterController

        _linkController = LinkController(rootManager: rootManager, itemController: itemController)
        
        _editController = EditController(root: self, itemController: itemController, linkController: linkController, sheetController: sheetController, tagController: searchModel.tagController)
        _exportController = ExportController(rootManager: rootManager, root: self, itemController: itemController)
        _gameController = GameController(rootManager: rootManager, root: self, itemController: itemController, exportController: exportController)
        editorLinkModel.rootManager = root
        editorLinkModel.folderListController = folderLinkController
        playerLinkModel.rootManager = root
        playerLinkModel.folderListController = folderLinkController

        audioRoot.setUp(context: context, batchContext: batchContext, rootManager: root, adventureRootControllable: self, linkRegisterController: linkRegisterController)
        diceRoot.setUp(context: context, batchContext: batchContext, rootManager: root, adventureRootControllable: self, linkRegisterController: linkRegisterController)
        pdfRoot.setUp(context: context, batchContext: batchContext, rootManager: root, adventureRootControllable: self, linkRegisterController: linkRegisterController)
        photoRoot.setUp(context: context, batchContext: batchContext, rootManager: root, adventureRootControllable: self, linkRegisterController: linkRegisterController)
        spaceRoot.setUp(context: context, batchContext: batchContext, rootManager: root, adventureRootControllable: self, linkRegisterController: linkRegisterController)
        weatherRoot.setUp(context: context, batchContext: batchContext, rootManager: root, adventureRootControllable: self, linkRegisterController: linkRegisterController)
        tableRoot.setUp(context: context, batchContext: batchContext, rootManager: root, adventureRootControllable: self, linkRegisterController: linkRegisterController)
        characterRoot.setUp(context: context, batchContext: batchContext, rootManager: root, adventureRootControllable: self, linkRegisterController: linkRegisterController)
        mapRoot.setUp(context: context, batchContext: batchContext, rootManager: root, adventureRootControllable: self, linkRegisterController: linkRegisterController)
#if !os(tvOS)
        generatorRoot?.setUp(context: context, batchContext: batchContext, rootManager: root, adventureRootControllable: self, linkRegisterController: linkRegisterController)
#endif

        syncTask?.cancel()
        if let dataControllable = itemController.itemDataModel.dataController, let context {
            let controller = SyncDataController(context: context, dataControllable: dataControllable, itemController: itemController)
            syncDataController = controller
            syncTask = controller.start()
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

    private var _rootManager: RootManager?
    public var rootManager: RootManager {
        get { _rootManager! }
        set { _rootManager = newValue }
    }
    private(set) var context: NSManagedObjectContext?

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

    @MainActor @ObservationIgnored private let _openFileWindowModel: OpenFileWindowModel = OpenFileWindowModel(windowId: NetworkModules.adventure.viewerWindowId, canShow: true) { DetailRoute.viewer($0) }
    @MainActor public var openFileWindowModel: OpenFileWindowModel { _openFileWindowModel }

    @ObservationIgnored var syncDataController: SyncDataController?
    @ObservationIgnored var syncTask: Task<Void, Never>?

    let itemController: ItemController
    @ObservationIgnored private var _linkController: LinkController?
    var linkController: LinkController { _linkController! }
    let sheetController: SheetController
    @ObservationIgnored private var _editController: EditController?
    var editController: EditController { _editController! }
    @ObservationIgnored private var _exportController: ExportController?
    var exportController: ExportController { _exportController! }
    @ObservationIgnored private var _importController: ImportController?
    var importController: ImportController {
        if let controller = _importController { return controller }
        let controller = ImportController(root: self, itemController: itemController)
        _importController = controller
        return controller
    }
    @ObservationIgnored private var _gameController: GameController?
    var gameController: GameController { _gameController! }
    @ObservationIgnored private var _searchController: SearchController?
    var searchController: SearchController {
        if let controller = _searchController { return controller }
        let controller = SearchController(itemController: itemController)
        _searchController = controller
        return controller
    }

    @ObservationIgnored private(set) var _linkRegisterController: LinkRegisterController?
    var linkRegisterController: LinkRegisterController { _linkRegisterController! }

    @MainActor @ObservationIgnored private var _folderListController: FolderListControllable?
    var folderListController: FolderListControllable {
        if let controller = _folderListController { return controller }
        let ldm = ListDisplayModel(displayMode: .compact)
        let controller = FolderListController(listModel: FolderListModel(isSelectionMode: false, selection: [], navigationModel: navigationModel), listDisplayModel: ldm, itemControllable: itemController, searchRootControllable: SearchListController(searchController: searchController, searchModel: searchModel, listDisplayModel: ldm))
        _folderListController = controller
        return controller
    }
    @MainActor @ObservationIgnored private var _folderLinkController: FolderListControllable?
    var folderLinkController: FolderListControllable {
        if let controller = _folderLinkController { return controller }
        let ldm = ListDisplayModel(displayMode: .compact)
        let controller = FolderListController(listModel: FolderListModel(isSelectionMode: false, selection: [], navigationModel: navigationModel), listDisplayModel: ldm, itemControllable: itemController, searchRootControllable: SearchLinkController(searchController: searchController, searchModel: searchModel.newSearchModel, listDisplayModel: ldm))
        _folderLinkController = controller
        return controller
    }
    @ObservationIgnored private let _viewController: ViewController = ViewController()
    public var viewController: ViewController { _viewController }

    @MainActor @ObservationIgnored private var _rootController: ItemRootController?
    @MainActor public var rootController: ItemRootController {
        if let controller = _rootController { return controller }
        let controller = ItemRootController(
            rootManager: rootManager,
            config: config,
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
            folderLinkControllable: folderLinkController,
            searchControllable: searchController,
            sheetControllable: sheetController,
            viewControllable: viewController
        )
        _rootController = controller
        return controller
    }
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
extension AdventureRootModel: RootExportControllable {
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
                await editController.delete(itemId: model.id)
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
