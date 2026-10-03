// @copyright André Trettin

import CoreRPG
import CoreData
import Foundation
import PhotoRPG
import SwiftUI

@MainActor @Observable
public final class WeatherRootModel {
    @MainActor init(tagController: TagController, photoRoot: PhotoRootModel) {
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

        self.photoRoot = photoRoot

        let itemController = ItemController(config: config)
        self.itemController = itemController
        let sheetController = SheetController(itemController: itemController)
        self.sheetController = sheetController
        let exportController = ExportController(photoRoot: photoRoot, itemController: itemController)
        self.exportController = exportController
        let gameController = GameController(itemController: itemController, exportController: exportController)
        self.gameController = gameController
        let linkController = LinkController(photoRoot: photoRoot, itemController: itemController, gameController: gameController)
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
        self.openFileWindowModel = OpenFileWindowModel(windowId: NetworkModules.weather.viewerWindowId, canShow: true, route: { DetailRoute.viewer($0) })

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

    let photoRoot: PhotoRootModel

    let itemController: ItemController
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
extension WeatherRootModel: ItemRootControllable {
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

extension WeatherRootModel {
    public var exportControllable: any ExportControllable {
        exportController as ExportControllable
    }
    public var importControllable: any ImportControllable {
        importController as ImportControllable
    }
    public var gameControllable: any GameControllable {
        gameController
    }
    public var weatherGameControllable: any WeatherGameControllable {
        gameController
    }
    public var searchControllable: any SearchControllable { searchController }
    @MainActor public var itemControllable: any ItemControllable {
        itemController
    }
}

public extension WeatherRootModel {
    @MainActor
    func listItems() -> [WeatherModel] {
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
