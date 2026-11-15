// @copyright André Trettin

import CoreRPG
import FoundationModels
import Foundation
import CoreData

@MainActor @Observable
public final class GeneratorRootModel {
    @MainActor init(tagController: TagController) {
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

        let itemController = ItemController(config: config)
        self.itemController = itemController
        let sheetController = SheetController(itemController: itemController)
        self.sheetController = sheetController
        let exportController = ExportController(itemController: itemController)
        self.exportController = exportController
        let gameController = GameController(itemController: itemController, exportController: exportController)
        self.gameController = gameController
        let linkController = LinkController(itemController: itemController)
        self.linkController = linkController
        let editController = EditController(itemController: itemController, tagController: tagController)
        self.editController = editController
        let importController = ImportController(itemController: itemController, editController: editController)
        self.importController = importController
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
            firstRow: [],
            selection: .none
        )
        self.openFileWindowModel = OpenFileWindowModel()

        self.rootController = ItemRootController(
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
            let controller = EntitySyncDataController(context: context, dataControllable: dataControllable, itemController: itemController, entity: RPGGenerator.entity())
            syncDataController = controller
            syncTask = controller.start()
        }
    }

    public let config: ModuleConfiguration
    @MainActor public var navigationModel: ModuleNavigationModel
    @ObservationIgnored public var itemSelectionModel: ItemSelectionModel
    @ObservationIgnored public var linkSelectionModel: ItemSelectionModel
    public let removeEntryListModel: RemoveEntryListModel

    let searchModel: SearchModel
    public let listDisplayModel: ListDisplayModel

    public var fileUrlDataController: FileUrlDataController? { itemController.fileUrlDataController }

    let itemController: ItemController
    @ObservationIgnored var exportController: ExportController
    @ObservationIgnored var gameController: GameController
    @ObservationIgnored var importController: ImportController
    @ObservationIgnored var linkController: LinkController
    @ObservationIgnored var searchController: SearchController
    let sheetController: SheetController
    @ObservationIgnored var editController: EditController
    @MainActor @ObservationIgnored public let rootController: ItemRootController
    @ObservationIgnored private let _viewController: ViewController
    public var viewController: ViewController { _viewController }
    
    @ObservationIgnored let folderListController: FolderListController
    @ObservationIgnored let folderLinkController: FolderListController

    @ObservationIgnored var syncDataController: EntitySyncDataController?
    @ObservationIgnored var syncTask: Task<Void, Never>?

    /// Scoped per item, not per module: a module-keyed dictionary meant two macOS/visionOS
    /// windows showing different items of the same module type shared one
    /// `GeneratorController` — activating "Ask AI" in one window silently rebuilt/cleared the
    /// other's conversation history and cancelled its in-flight generation via the shared
    /// `currentTask`. Bounded with FIFO eviction (mirroring `MasterController`'s
    /// `playerJournalAdmissions` pattern) so visiting many sheets over a long session doesn't
    /// grow this indefinitely. See CODE_AUDIT §5.8.
    @MainActor @ObservationIgnored private var generatorControllers: [UUID: GeneratorController] = [:]
    @MainActor @ObservationIgnored private var generatorControllerOrder: [UUID] = []
    private static let maximumGeneratorControllers = 12

    /// Returns this item's `GeneratorController`, creating one on first access. See the
    /// `generatorControllers` doc comment for why this is keyed by item rather than module.
    @MainActor func generatorController(forItem itemId: UUID) -> GeneratorController {
        if let existing = generatorControllers[itemId] {
            // Least recently used: a controller that is asked for again moves to the end.
            if generatorControllerOrder.last != itemId {
                generatorControllerOrder.removeAll { $0 == itemId }
                generatorControllerOrder.append(itemId)
            }
            return existing
        }
        let controller = GeneratorController()
        generatorControllers[itemId] = controller
        generatorControllerOrder.append(itemId)
        evictGeneratorControllers(keeping: itemId)
        return controller
    }

    /// Drops the least recently used controllers beyond the limit, but never one that is
    /// generating or extracting (its window may still be on screen), nor `keptItemId`. The limit
    /// is a soft one while such controllers exist. See CODE_AUDIT_26 §7.17.
    @MainActor private func evictGeneratorControllers(keeping keptItemId: UUID) {
        var index = 0
        while generatorControllerOrder.count > Self.maximumGeneratorControllers,
              index < generatorControllerOrder.count {
            let candidateId = generatorControllerOrder[index]
            guard candidateId != keptItemId,
                  let candidate = generatorControllers[candidateId],
                  !candidate.model.isLoading, !candidate.model.isExtracting else {
                index += 1
                continue
            }
            generatorControllerOrder.remove(at: index)
            candidate.tearDown()
            generatorControllers[candidateId] = nil
        }
    }

    /// Whether the on-device model can be used at all. Checked before a controller is made, so a
    /// device without Apple Intelligence does not allocate an engine and a session for every
    /// sheet it visits. See CODE_AUDIT_26 §7.17.
    @MainActor static var isAssistantModelAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    @MainActor @ObservationIgnored let editorLinkModel: EditorLinkModel
    @MainActor @ObservationIgnored public let openFileWindowModel: OpenFileWindowModel
}

@MainActor
extension GeneratorRootModel: ItemRootControllable {
    @MainActor public var currentSelectedItemId: UUID? { folderListController.listModel.selectedItemId }

    public var rootManager: RootManager? { rootController.rootManager }
    public var configurable: any ModuleConfigurable { config }
    public var cacheControllable: (any ImageCacheControllable)? { nil }
    public var editControllable: any EditControllable { editController }
    public var exportControllable: any ExportControllable { exportController }
    public var gameControllable: any GameControllable { gameController }
    public var importControllable: any ImportControllable { importController }
    public var itemControllable: any ItemControllable { itemController }
    public var linkControllable: any LinkControllable { linkController }
    public var folderListControllable: any FolderListControllable { folderListController }
    public var folderLinkControllable: any FolderListControllable { folderLinkController }
    public var inspectorEditorLinkModel: EditorLinkModel? { editorLinkModel }
    public var searchControllable: any SearchControllable { searchController }
    public var sheetControllable: any SheetControllable { sheetController }
    public var viewControllable: any ViewControllable { viewController }
}
