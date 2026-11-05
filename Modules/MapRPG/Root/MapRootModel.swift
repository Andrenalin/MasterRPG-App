// @copyright André Trettin

import CoreRPG
import CoreData
import DiceRPG
import AudioRPG
#if !os(tvOS)
import GeneratorRPG
#endif
import PdfRPG
import PhotoRPG
import TableRPG
import CharacterRPG
import SwiftUI

@MainActor @Observable
public final class RootModel: Sendable {
    @MainActor
    var gameEditorModel: MapEditorSession? = nil

    /// The game toolbar's "Share Map" state — one value for the 2D map and the 3D table, so
    /// pausing sharing in one mode pauses it in the other. On by default and again at every game
    /// start (`GameController.startGameAsMaster`).
    @MainActor public var isMapStreaming = true

    /// Maps whose entry structure (e.g. the 3D table's hex grid toggle) changed while sharing
    /// was paused, so the structural content update was never sent. The next explicit send
    /// must push it before the map state. See CODE_AUDIT_19 §3.12.
    @ObservationIgnored
    @MainActor public var mapsWithUnsharedStructure: Set<UUID> = []

    /// Tail of the chain every game-master send of a map's content update goes through, shared by
    /// the 2D map, the 3D table and "Refresh Shared Map" so two content updates always reach the
    /// players in the order they were made. See CODE_AUDIT_19 §3.12, CODE_AUDIT_20 §3.1.
    @ObservationIgnored
    @MainActor private var mapContentSendTail: Task<Void, Never>?

    /// Runs `work` after every earlier enqueued send has finished.
    @MainActor public func enqueueMapContentSend(_ work: @escaping @MainActor () async -> Void) {
        let previous = mapContentSendTail
        mapContentSendTail = Task { @MainActor in
            await previous?.value
            await work()
        }
    }

    /// The game master's player/reader preview, shared by the 2D map session and the 3D table.
    /// Each 2D↔3D toggle builds a new table model, which used to start at `.master` again.
    /// See CODE_AUDIT_19 §5.17.
    @MainActor public var gameDisplayMode: MapDisplayMode {
        get { gameEditorModel?.displayMode ?? retainedGameDisplayMode }
        set {
            retainedGameDisplayMode = newValue
            if let gameEditorModel, gameEditorModel.mapMode == .gameMaster {
                gameEditorModel.displayMode = newValue
            }
        }
    }
    @ObservationIgnored
    @MainActor private var retainedGameDisplayMode: MapDisplayMode = .master

    /// The game screen retains its map session across map replacement so the
    /// bottom toolbar does not blink out. The owning game screen clears that
    /// retained session explicitly when the whole screen leaves the hierarchy.
    @MainActor public func clearGameEditorSession() {
        gameEditorModel = nil
    }
}

@MainActor @Observable
public final class MapRootModel {

    @MainActor
    init(tagController: TagController, audioRoot: AudioRootModel, diceRoot: DiceRootModel, generatorRoot: GeneratorRootModel? = nil, pdfRoot: PdfRootModel, photoRoot: PhotoRootModel, tableRoot: TableRootModel, characterRoot: CharacterRootModel) {
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
        self.pdfRoot = pdfRoot
        self.photoRoot = photoRoot
        self.tableRoot = tableRoot
        self.characterRoot = characterRoot
        self.rootModel = RootModel()


        let itemController = ItemController(config: config, photoRoot: photoRoot)
        self.itemController = itemController
        self.sheetController = SheetController(itemController: itemController)
        let searchController = SearchController(itemController: itemController)
        self.searchController = searchController
        self._viewController = ViewController()

        let folderListModel = FolderListModel(isSelectionMode: false, selection: [], navigationModel: navigationModel)
        let folderListController = FolderListController(listModel: folderListModel, listDisplayModel: listDisplayModel, itemControllable: itemController, searchRootControllable: SearchListController(searchController: searchController, searchModel: searchModel, listDisplayModel: listDisplayModel))
        self.folderListController = folderListController

        let folderLinkModel = FolderListModel(isSelectionMode: false, selection: [], navigationModel: navigationModel)
        let linkDisplayModel = listDisplayModel.newListDisplayModel
        let folderLinkController = FolderListController(listModel: folderLinkModel, listDisplayModel: linkDisplayModel, itemControllable: itemController, searchRootControllable: SearchLinkController(searchController: searchController, searchModel: searchModel.newSearchModel, listDisplayModel: linkDisplayModel))
        self.folderLinkController = folderLinkController

        self.editorLinkModel = EditorLinkModel(
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
        self.openFileWindowModel = OpenFileWindowModel(windowId: NetworkModules.map.viewerWindowId, route: { DetailRoute.viewer($0) })
    }

    @MainActor public func setUp(context: NSManagedObjectContext?, rootManager: RootManager, adventureRootControllable: any RootExportControllable, linkRegisterController: LinkRegisterController) {
        rootController.rootManager = rootManager

        itemController.itemDataModel.dataController = context.map { DataController(context: $0, token: config.module.token) }
        itemController.itemDataModel.linkRegisterController = linkRegisterController

        exportController.hubControllable = adventureRootControllable
        editController.editorModel.sheetRootModel = SheetRootModel(
            rootManager: rootManager,
            linkControllable: linkController,
            sheetControllable: sheetController,
            itemId: UUID(),
            isEditor: true,
            editorModel: editController.editorModel.sheetEditorModel
        )
        editorLinkModel.rootManager = rootManager

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
    let pdfRoot: PdfRootModel
    let photoRoot: PhotoRootModel
    let tableRoot: TableRootModel
    let characterRoot: CharacterRootModel

    public let rootModel: RootModel
    /// A photo the game master shows on the game map. GameRPG sets it; the 2D map and the 3D
    /// table draw it.
    public let photoPopover = MapPhotoPopoverModel()

    public let config: ModuleConfiguration
    @MainActor public var navigationModel: ModuleNavigationModel
    @ObservationIgnored public var itemSelectionModel: ItemSelectionModel
    @ObservationIgnored public var linkSelectionModel: ItemSelectionModel
    public let removeEntryListModel: RemoveEntryListModel

    public let listDisplayModel: ListDisplayModel
    let searchModel: SearchModel

    var cacheController: CacheController? { itemController.cacheController }

    let itemController: ItemController
    let sheetController: SheetController

    @ObservationIgnored lazy var linkController: LinkController = {
        LinkController(root: self, audioRoot: audioRoot, diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot, characterRoot: characterRoot, itemController: itemController)
    }()
    @ObservationIgnored lazy var editController: EditController = {
        EditController(root: self, itemController: itemController, tagController: searchModel.tagController)
    }()
    @ObservationIgnored lazy var exportController: ExportController = {
        ExportController(root: self, audioRoot: audioRoot, diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot, characterRoot: characterRoot, itemController: itemController)
    }()
    @ObservationIgnored lazy var importController: ImportController = {
        ImportController(itemController: itemController, editController: editController)
    }()
    @ObservationIgnored lazy var gameController: GameController = {
        GameController(root: self, itemController: itemController, exportController: exportController)
    }()
    @ObservationIgnored var searchController: SearchController

    @MainActor @ObservationIgnored public lazy var rootController: ItemRootController = {
        ItemRootController(
            rootManager: nil,
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
    @MainActor @ObservationIgnored public let openFileWindowModel: OpenFileWindowModel
}

@MainActor
extension MapRootModel: ItemRootControllable {
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
        MapActions(id: .object(ObjectIdentifier(self)), quickMap: editController.generateQuickMap(name:photoId:))
    }
}

public extension MapRootModel {
    /// Toggles the hex overlay grid for the given map, generating or clearing
    /// its grid entries. Wraps the MapRPG-internal `EditController` so other
    /// modules (GameRPG's 3D table toolbar) can reuse the exact same
    /// grid-generation logic the 2D map editor uses.
    @discardableResult
    @MainActor
    func toggleHexMap(itemId: UUID) -> Bool {
        editController.toggleHexMap(for: gameController.gameItem(for: itemId))
    }

    /// Rebuilds the hex grid of the game map `itemId` for `scale`, keeping the revealed area.
    /// Public for the 3D table, like `toggleHexMap(itemId:)`. See CODE_AUDIT_21 §5.19.
    @MainActor
    func rescaleHexMap(itemId: UUID, scale: Double) {
        editController.createHexMap(model: gameController.gameItem(for: itemId), hexMapScale: scale)
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
