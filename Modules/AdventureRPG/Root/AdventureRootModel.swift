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
import RuleRPG
import SpaceRPG
import SwiftUI
import TableRPG
import WeatherRPG

@MainActor @Observable
public final class AdventureRootModel {

    @MainActor
    init(tagController: TagController, audioRoot: AudioRootModel, diceRoot: DiceRootModel, generatorRoot: GeneratorRootModel?, mapRoot: MapRootModel, pdfRoot: PdfRootModel, photoRoot: PhotoRootModel, ruleRoot: RuleRootModel, spaceRoot: SpaceRootModel, tableRoot: TableRootModel, characterRoot: CharacterRootModel, weatherRoot: WeatherRootModel) {
        let config = ModuleConfiguration()
        self.config = config

        let navigationModel = ModuleNavigationModel()
        self.navigationModel = navigationModel
        let itemSelectionModel = ItemSelectionModel()
        self.itemSelectionModel = itemSelectionModel
        self.linkSelectionModel = config.linkSelectionModel
        self.removeEntryListModel = RemoveEntryListModel()

        let searchModel = SearchModel(tagController: tagController, module: config.module, categoryTags: config.categoryTags)
        self.searchModel = searchModel
        let listDisplayModel = ListDisplayModel()
        self.listDisplayModel = listDisplayModel

        self.audioRoot = audioRoot
        self.diceRoot = diceRoot
        self.generatorRoot = generatorRoot
        self.mapRoot = mapRoot
        self.pdfRoot = pdfRoot
        self.photoRoot = photoRoot
        self.ruleRoot = ruleRoot
        self.spaceRoot = spaceRoot
        self.tableRoot = tableRoot
        self.characterRoot = characterRoot
        self.weatherRoot = weatherRoot

        let itemController = ItemController(config: config)
        self.itemController = itemController
        let sheetController = SheetController(itemController: itemController)
        self.sheetController = sheetController
        let linkController = LinkController(itemController: itemController)
        self.linkController = linkController
        let searchController = SearchController(itemController: itemController)
        self.searchController = searchController
        self._viewController = ViewController()

        let folderListDisplayModel = ListDisplayModel(displayMode: .compact)
        let folderListModel = FolderListModel(isSelectionMode: false, selection: [], navigationModel: navigationModel)
        let folderListController = FolderListController(listModel: folderListModel, listDisplayModel: folderListDisplayModel, itemControllable: itemController, searchRootControllable: SearchListController(searchController: searchController, searchModel: searchModel, listDisplayModel: folderListDisplayModel))
        self.folderListController = folderListController

        let folderLinkDisplayModel = ListDisplayModel(displayMode: .compact)
        let folderLinkModel = FolderListModel(isSelectionMode: false, selection: [], navigationModel: navigationModel)
        let folderLinkController = FolderListController(listModel: folderLinkModel, listDisplayModel: folderLinkDisplayModel, itemControllable: itemController, searchRootControllable: SearchLinkController(searchController: searchController, searchModel: searchModel.newSearchModel, listDisplayModel: folderLinkDisplayModel))
        self.folderLinkController = folderLinkController

        self.editorLinkModel = EditorLinkModel(
            folderListController: folderLinkController,
            adventureSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: true),
            audioSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false),
            characterSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false),
            diceSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false),
            mapSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: true),
            pdfSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: true),
            photoSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false),
            ruleSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: true),
            spaceSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false),
            tableSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: true),
            weatherSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false),
            firstRow: [.adventure, .map, .value, .rule, .table, .weather],
            secondRow: [.audio, .dice, .pdf, .photo, .space],
            selection: .map
        )
        self.playerLinkModel = EditorLinkModel(
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
        self.openFileWindowModel = OpenFileWindowModel(windowId: NetworkModules.adventure.viewerWindowId, canShow: true) { DetailRoute.viewer($0) }
    }

    @MainActor public func setUp(root: RootManager, context: NSManagedObjectContext?, batchContext: NSManagedObjectContext?) {
        let linkRegisterController = LinkRegisterController(root: root)
        linkRegisterController.setup(context: context)

        itemController.itemDataModel.dataController = context.map { DataController(context: $0, token: config.module.token) }
        itemController.itemDataModel.linkRegisterController = linkRegisterController

        linkController.rootManager = root
        exportController.rootManager = root
        rootController.rootManager = root

        editController.editorModel.sheetRootModel = SheetRootModel(
            rootManager: root,
            linkControllable: linkController,
            sheetControllable: sheetController,
            itemId: UUID(),
            isEditor: true,
            editorModel: editController.editorModel.sheetEditorModel
        )
        editorLinkModel.rootManager = root
        playerLinkModel.rootManager = root

        audioRoot.setUp(context: context, batchContext: batchContext, rootManager: root, adventureRootControllable: self, linkRegisterController: linkRegisterController)
        diceRoot.setUp(context: context, batchContext: batchContext, rootManager: root, adventureRootControllable: self, linkRegisterController: linkRegisterController)
        pdfRoot.setUp(context: context, batchContext: batchContext, rootManager: root, adventureRootControllable: self, linkRegisterController: linkRegisterController)
        photoRoot.setUp(context: context, batchContext: batchContext, rootManager: root, adventureRootControllable: self, linkRegisterController: linkRegisterController)
        ruleRoot.setUp(context: context, batchContext: batchContext, rootManager: root, adventureRootControllable: self, linkRegisterController: linkRegisterController)
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
    let ruleRoot: RuleRootModel
    let spaceRoot: SpaceRootModel
    let tableRoot: TableRootModel
    let characterRoot: CharacterRootModel
    let weatherRoot: WeatherRootModel

    public let config: ModuleConfiguration
    @MainActor public var navigationModel: ModuleNavigationModel
    @ObservationIgnored public var itemSelectionModel: ItemSelectionModel
    @ObservationIgnored public var linkSelectionModel: ItemSelectionModel
    public let removeEntryListModel: RemoveEntryListModel

    public let listDisplayModel: ListDisplayModel
    let searchModel: SearchModel

    let itemController: ItemController
    @ObservationIgnored var linkController: LinkController
    let sheetController: SheetController
    @ObservationIgnored lazy var editController: EditController = {
        EditController(root: self, itemController: itemController, linkController: linkController, sheetController: sheetController, tagController: searchModel.tagController)
    }()
    @ObservationIgnored lazy var exportController: ExportController = {
        ExportController(root: self, itemController: itemController)
    }()
    @ObservationIgnored lazy var importController: ImportController = {
        ImportController(root: self, itemController: itemController)
    }()
    @ObservationIgnored lazy var gameController: GameController = {
        GameController(root: self, itemController: itemController, exportController: exportController)
    }()
    @ObservationIgnored var searchController: SearchController

    // Aligns with the other 10 modules' root models: there's no separate optional-storage
    // force-unwrapped accessor here, just the shared `ItemControllable.linkRegisterController`
    // default (CODE_AUDIT §5.5), which fails with a diagnostic message instead of a bare `!`
    // if read before `setUp(root:context:batchContext:)` runs.
    @ObservationIgnored var linkRegisterController: LinkRegisterController { itemController.linkRegisterController }

    @MainActor @ObservationIgnored public lazy var rootController: ItemRootController = {
        ItemRootController(
            rootManager: nil,
            config: config,
            navigationModel: navigationModel,
            inspectorEditorLinkModel: editorLinkModel,
            openFileWindowModel: openFileWindowModel,
            itemSelectionModel: itemSelectionModel,
            removeEntryListModel: removeEntryListModel,
            cacheControllable: nil,
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
            viewControllable: _viewController
        )
    }()
    @ObservationIgnored private let _viewController: ViewController
    public var viewController: ViewController { _viewController }

    @ObservationIgnored let folderListController: FolderListController
    @ObservationIgnored let folderLinkController: FolderListController

    @ObservationIgnored var syncDataController: SyncDataController?
    @ObservationIgnored var syncTask: Task<Void, Never>?

    @MainActor @ObservationIgnored let editorLinkModel: EditorLinkModel
    @MainActor @ObservationIgnored let playerLinkModel: EditorLinkModel
    @MainActor @ObservationIgnored public let openFileWindowModel: OpenFileWindowModel
}

@MainActor
extension AdventureRootModel: ItemRootControllable {
    @MainActor public var currentSelectedItemId: UUID? { folderListController.listModel.selectedItemId }

    public var rootManager: RootManager? { rootController.rootManager }
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
        for root in siblingModuleRoots {
            await root.itemControllable.resetData()
        }
        await linkRegisterController.resetData()
        await searchModel.tagController.resetData()
    }

    @Sendable public func save() async {
        // Flush all module pending operations into the shared context without saving yet.
        for root in siblingModuleRoots {
            await root.itemControllable.flushPendingOperations()
        }
        #if !os(tvOS)
        await generatorRoot?.itemControllable.flushPendingOperations()
        #endif
        await linkRegisterController.savePendingLinks()
        await searchModel.tagController.savePendingTags()
        // One context.save() covers all flushed changes from every module above.
        await itemController.save()
    }

    /// Flushes a reviewed partial import and surfaces persistence failures to the caller.
    /// External import uses this boundary so it can roll back newly installed attachments when
    /// the consolidated Core Data save fails.
    @Sendable public func saveExternalImport() async throws {
        for root in siblingModuleRoots {
            try await root.itemControllable.dataControllable?.flushPendingOperations()
        }
        #if !os(tvOS)
        try await generatorRoot?.itemControllable.dataControllable?.flushPendingOperations()
        #endif
        await linkRegisterController.savePendingLinks()
        await searchModel.tagController.savePendingTags()
        try await itemController.dataControllable?.save()
        AppIntentContentInvalidator.invalidate()
    }

    public func validate() {
        Task { @MainActor in
            let report = ValidateRepairModel()

            report.update(phase: .repairFolders)
            await checkFolders(reportModel: report)
            for root in siblingModuleRoots {
                await root.checkFolders(reportModel: report)
            }

            report.update(phase: .validateLinks)
            await validateLinks(reportModel: report)
            for root in siblingModuleRoots {
                await root.validateLinks(reportModel: report)
            }
        }
    }
}

// MARK: - Game

public extension AdventureRootModel {
    @MainActor func startGame() {
        itemController.itemDataModel.isGameMode = true
        for root in siblingModuleRoots {
            root.itemControllable.itemDataModel.isGameMode = true
        }
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
            if model.displayState == DisplayStateMask.totalHidden.rawValue {
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
