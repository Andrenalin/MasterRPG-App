// @copyright André Trettin

import CoreRPG
import CoreData
import DiceRPG
#if !os(tvOS)
import GeneratorRPG
#endif
import PdfRPG
import SwiftData
import SwiftUI

@MainActor @Observable
public final class TableRootModel {
    @MainActor init(tagController: TagController, diceRoot: DiceRootModel, generatorRoot: GeneratorRootModel? = nil, pdfRoot: PdfRootModel) {
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

        self.diceRoot = diceRoot
        self.generatorRoot = generatorRoot
        self.pdfRoot = pdfRoot

        let itemController = ItemController(config: config)
        self.itemController = itemController
        let generationRootManagerBox = TableGenerationRootManagerBox()
        let generationController = TableGenerationController(
            itemController: itemController,
            diceRoot: diceRoot,
            rootManagerBox: generationRootManagerBox
        )
        self.generationController = generationController
        let generationSessionStore = TableGenerationSessionStore(
            controller: generationController
        )
        self.generationSessionStore = generationSessionStore
        let generationViewController = TableGenerationViewController(
            controller: generationController,
            sessionStore: generationSessionStore
        )
        self.generationViewController = generationViewController
        let sheetController = SheetController(itemController: itemController)
        self.sheetController = sheetController
        let exportController = ExportController(diceRoot: diceRoot, pdfRoot: pdfRoot, itemController: itemController)
        self.exportController = exportController
        let gameController = GameController(
            diceRoot: diceRoot,
            itemController: itemController,
            exportController: exportController,
            generationSessionStore: generationSessionStore
        )
        self.gameController = gameController
        let linkController = LinkController(diceRoot: diceRoot, itemController: itemController, gameController: gameController)
        self.linkController = linkController
        let editController = EditController(diceRoot: diceRoot, itemController: itemController, linkController: linkController, sheetController: sheetController, tagController: tagController)
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
            diceSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false),
            pdfSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: true),
            tableSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: true),
            firstRow: [.dice, .pdf, .table],
            selection: .table
        )
        self.openFileWindowModel = OpenFileWindowModel(windowId: NetworkModules.table.viewerWindowId, canShow: true) { DetailRoute.viewer($0) }

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
            viewControllable: _viewController,
            generationControllable: generationViewController
        )
    }

    @MainActor public func setUp(context: NSManagedObjectContext?, batchContext: NSManagedObjectContext?, rootManager: RootManager, adventureRootControllable: any RootExportControllable, linkRegisterController: LinkRegisterController) {
        rootController.rootManager = rootManager
        generationController.rootManagerBox.rootManager = rootManager

        itemController.itemDataModel.dataController = context.map { DataController(context: $0, batchContext: batchContext, token: config.module.token) }
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

    public let config: ModuleConfiguration
    @MainActor public var navigationModel: ModuleNavigationModel
    @ObservationIgnored public var itemSelectionModel: ItemSelectionModel
    @ObservationIgnored public var linkSelectionModel: ItemSelectionModel
    public let removeEntryListModel: RemoveEntryListModel

    let searchModel: SearchModel
    let listDisplayModel: ListDisplayModel

    let diceRoot: DiceRootModel
    let generatorRoot: GeneratorRootModel?
    let pdfRoot: PdfRootModel

    let itemController: ItemController
    @ObservationIgnored let generationController: TableGenerationController
    @ObservationIgnored let generationSessionStore: TableGenerationSessionStore
    @ObservationIgnored let generationViewController: TableGenerationViewController
    let sheetController: SheetController
    
    @ObservationIgnored var exportController: ExportController
    @ObservationIgnored var gameController: GameController
    @ObservationIgnored var importController: ImportController
    @ObservationIgnored var linkController: LinkController
    @ObservationIgnored var searchController: SearchController
    @ObservationIgnored var editController: EditController
    @MainActor @ObservationIgnored public let rootController: ItemRootController
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
extension TableRootModel: ItemRootControllable {
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

extension TableRootModel {
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
    public var tableGameControllable: any (GameControllable & TableGameStorable) {
        gameController
    }
}

// Other

public extension TableRootModel {
    @MainActor
    func listItems() -> [TableModel] {
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
