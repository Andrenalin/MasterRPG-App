// @copyright André Trettin

import CoreRPG
import CoreData
import DiceRPG
import AudioRPG
import PdfRPG
import PhotoRPG
import TableRPG
import CharacterRPG
import SwiftData
import SwiftUI

@MainActor @Observable
public final class RootModel: Sendable {
    @MainActor
    var gameEditorModel: MapEditorModel? = nil
}

@MainActor @Observable
public final class MapRootModel {

    @MainActor
    init(tagController: TagController, audioRoot: AudioRootModel, diceRoot: DiceRootModel, pdfRoot: PdfRootModel, photoRoot: PhotoRootModel, tableRoot: TableRootModel, characterRoot: CharacterRootModel) {
        self.audioRoot = audioRoot
        self.diceRoot = diceRoot
        self.pdfRoot = pdfRoot
        self.photoRoot = photoRoot
        self.tableRoot = tableRoot
        self.characterRoot = characterRoot

        rootModel = RootModel()

        let config = ModuleConfiguration()
        self.config = config

        let listDisplayModel = ListDisplayModel()
        self.listDisplayModel = listDisplayModel
        let searchModel = SearchModel(tagController: tagController, module: config.module, categoryTags: config.categoryTags)
        self.searchModel = searchModel

        self.itemSelectionModel = ItemSelectionModel()
        self.navigationModel = ModuleNavigationModel()
        self.linkSelectionModel = config.linkSelectionModel

        let itemController = ItemController(config: config, photoRoot: photoRoot)
        self.itemController = itemController
        self.sheetController = SheetController(itemController: itemController)
    }

    @MainActor public func setUp(context: NSManagedObjectContext?, batchContext: NSManagedObjectContext?, rootManager: RootManager, adventureRootControllable: any RootExportControllable, linkRegisterController: LinkRegisterController) {
        self.context = context
        self.batchContext = batchContext
        self.rootManager = rootManager
        self._adventureRootControllable = adventureRootControllable
        self._linkRegisterController = linkRegisterController

        _importController = nil
        _searchController = nil
        _folderListController = nil
        _folderLinkController = nil
        _rootController = nil

        itemController.itemDataModel.dataController = context.map { DataController(context: $0, batchContext: batchContext, token: config.module.token) }
        itemController.itemDataModel.linkRegisterController = linkRegisterController

        _editController = EditController(root: self, itemController: itemController, linkController: linkController, sheetController: sheetController, tagController: searchModel.tagController)
        exportController.hubControllable = adventureRootControllable

        syncTask?.cancel()
        if let dataControllable = itemController.itemDataModel.dataController, let context {
            let controller = SyncDataController(context: context, dataControllable: dataControllable, itemController: itemController)
            syncDataController = controller
            syncTask = controller.start()
        }
    }

    let audioRoot: AudioRootModel
    let diceRoot: DiceRootModel
    let pdfRoot: PdfRootModel
    let photoRoot: PhotoRootModel
    let tableRoot: TableRootModel
    let characterRoot: CharacterRootModel

    public let rootModel: RootModel

    private var _rootManager: RootManager?
    public var rootManager: RootManager {
        get { _rootManager! }
        set { _rootManager = newValue }
    }
    private(set) var context: NSManagedObjectContext?
    private(set) var batchContext: NSManagedObjectContext?
    private var _adventureRootControllable: (any RootExportControllable)?
    var adventureRootControllable: any RootExportControllable { _adventureRootControllable! }
    private var _linkRegisterController: LinkRegisterController?
    var linkRegisterController: LinkRegisterController { _linkRegisterController! }

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
            rootManager: RootManager(adventureRoot: self, audioRoot: audioRoot, characterRoot: characterRoot, diceRoot: diceRoot, generatorRoot: self, mapRoot: self, pdfRoot: pdfRoot, photoRoot: photoRoot, spaceRoot: self, tableRoot: tableRoot, weatherRoot: self),
            folderListController: folderLinkController,
            audioSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false),
            characterSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false),
            diceSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false),
            mapSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: true),
            pdfSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: true),
            photoSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false),
            tableSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: true),
            firstRow: [.map, .value, .table, .photo, .audio, .dice],
            selection: .value
        )
    }()

    @MainActor @ObservationIgnored lazy public var openFileWindowModel: OpenFileWindowModel = { OpenFileWindowModel(windowId: NetworkModules.map.viewerWindowId, route: { DetailRoute.viewer($0) })
    }()

    var cacheController: CacheController? { itemController.cacheController }
    @ObservationIgnored var syncDataController: SyncDataController?
    @ObservationIgnored var syncTask: Task<Void, Never>?

    let itemController: ItemController
    let sheetController: SheetController


    @ObservationIgnored lazy var linkController: LinkController = {
        LinkController(root: self, audioRoot: audioRoot, diceRoot: diceRoot, photoRoot: photoRoot, tableRoot: tableRoot, characterRoot: characterRoot, itemController: itemController)
    }()
    @ObservationIgnored private var _editController: EditController?
    var editController: EditController { _editController! }
    @ObservationIgnored lazy var exportController: ExportController = {
        ExportController(root: self, audioRoot: audioRoot, diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot, characterRoot: characterRoot, itemController: itemController)
    }()
    @ObservationIgnored private var _importController: ImportController?
    var importController: ImportController {
        if let controller = _importController { return controller }
        let controller = ImportController(itemController: itemController, editController: editController)
        _importController = controller
        return controller
    }
    @ObservationIgnored lazy var gameController: GameController = {
        GameController(root: self, itemController: itemController, exportController: exportController)
    }()
    @ObservationIgnored private var _searchController: SearchController?
    var searchController: SearchController {
        if let controller = _searchController { return controller }
        let controller = SearchController(itemController: itemController)
        _searchController = controller
        return controller
    }

    @ObservationIgnored private var _folderListController: FolderListControllable?
    var folderListController: FolderListControllable {
        if let controller = _folderListController { return controller }
        let controller = FolderListController(listModel: FolderListModel(isSelectionMode: false, selection: [], navigationModel: navigationModel), listDisplayModel: listDisplayModel, itemControllable: itemController, searchRootControllable: SearchListController(searchController: searchController, searchModel: searchModel, listDisplayModel: listDisplayModel))
        _folderListController = controller
        return controller
    }

    @ObservationIgnored private var _folderLinkController: FolderListControllable?
    var folderLinkController: FolderListControllable {
        if let controller = _folderLinkController { return controller }
        let linkDisplayModel = listDisplayModel.newListDisplayModel
        let controller = FolderListController(listModel: FolderListModel(isSelectionMode: false, selection: [], navigationModel: navigationModel), listDisplayModel: linkDisplayModel, itemControllable: itemController, searchRootControllable: SearchLinkController(searchController: searchController, searchModel: searchModel.newSearchModel, listDisplayModel: linkDisplayModel))
        _folderLinkController = controller
        return controller
    }

    @ObservationIgnored public lazy var viewController: ViewController = {
        ViewController()
    }()

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
            cacheControllable: cacheController,
            editControllable: editController,
            exportControllable: exportController,
            gameControllable: gameController,
            importControllable: importController,
            itemControllable: itemController,
            linkControllable: linkController,
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
extension MapRootModel: ItemRootControllable {
    public var configurable: any ModuleConfigurable { config }
    public var cacheControllable: (any ImageCacheControllable)? { nil }
    public var editControllable: any EditControllable { editController }
    public var folderListControllable: any FolderListControllable { folderListController }
    public var folderLinkControllable: any FolderListControllable { folderLinkController }
    public var inspectorEditorLinkModel: EditorLinkModel? { editorLinkModel }
    public var sheetControllable: any SheetControllable { sheetController }
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
    @MainActor public var itemControllable: any ItemControllable {
        itemController
    }
    public var searchControllable: any SearchControllable { searchController }
    public var mapGameControllable: any (GameControllable & MapGameStorable) {
        gameController
    }
}

// MARK: - Actions

extension MapRootModel {
    @MainActor
    public var mapActions: MapActions {
        MapActions(quickMap: editController.generateQuickMap(name:photoId:))
    }
}

public extension MapRootModel {
    @MainActor
    func listItems() -> [MapModel] {
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
