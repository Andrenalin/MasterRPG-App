// @copyright André Trettin

import AVFoundation
import CoreRPG
import CoreData
import SwiftUI

@MainActor @Observable public final class AudioRootModel {
    @MainActor init(tagController: TagController) {
        let config = ModuleConfiguration()
        self.config = config

        let navigationModel = ModuleNavigationModel()
        self.navigationModel = navigationModel
        self.itemSelectionModel = ItemSelectionModel()
        self.linkSelectionModel = config.linkSelectionModel
        self.removeEntryListModel = RemoveEntryListModel()

        let searchModel = SearchModel(tagController: tagController, module: config.module, categoryTags: config.categoryTags)
        self.searchModel = searchModel
        let listDisplayModel = ListDisplayModel()
        self.listDisplayModel = listDisplayModel
        
        let audioPlayerModel = AudioPlayerModel()
        self.audioPlayerModel = audioPlayerModel

        let itemController = ItemController(config: config)
        self.itemController = itemController
        let audioController = AudioController(itemController: itemController, model: audioPlayerModel)
        self.audioController = audioController
        let sheetController = SheetController(itemController: itemController)
        self.sheetController = sheetController
        let exportController = ExportController(itemController: itemController)
        self.exportController = exportController
        let gameController = GameController(itemController: itemController, audioController: audioController, exportController: exportController)
        self.gameController = gameController
        let linkController = LinkController(itemController: itemController, audioController: audioController, gameController: gameController)
        self.linkController = linkController
        let editController = EditController(itemController: itemController, tagController: tagController)
        self.editController = editController
        let importController = ImportController(itemController: itemController, editController: editController)
        self.importController = importController
        let searchController = SearchController(itemController: itemController)
        self.searchController = searchController
        self.viewController = ViewController()
        
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
            viewControllable: viewController
        )
    }

    @MainActor public func setUp(context: NSManagedObjectContext?, rootManager: RootManager, adventureRootControllable: any RootExportControllable, linkRegisterController: LinkRegisterController) {
        rootController.rootManager = rootManager
        
        itemController.itemDataModel.dataController = context.map { DataController(context: $0, token: config.module.token) }
        itemController.itemDataModel.linkRegisterController = linkRegisterController

        exportController.exportModel.hubControllable = adventureRootControllable
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
    
    public let audioPlayerModel: AudioPlayerModel

    @ObservationIgnored let audioController: AudioController
    @ObservationIgnored let itemController: ItemController
    @ObservationIgnored let editController: EditController
    @ObservationIgnored let exportController: ExportController
    @ObservationIgnored let gameController: GameController
    @ObservationIgnored let importController: ImportController
    @ObservationIgnored let linkController: LinkController
    @ObservationIgnored let searchController: SearchController
    @ObservationIgnored let sheetController: SheetController
    @MainActor @ObservationIgnored public let rootController: ItemRootController
    @ObservationIgnored public let viewController: ViewController

    @ObservationIgnored let folderListController: FolderListController
    @ObservationIgnored let folderLinkController: FolderListController

    @ObservationIgnored var syncDataController: SyncDataController?
    @ObservationIgnored var syncTask: Task<Void, Never>?

    @MainActor @ObservationIgnored let editorLinkModel: EditorLinkModel
    @MainActor @ObservationIgnored public let openFileWindowModel: OpenFileWindowModel
}

@MainActor extension AudioRootModel: ItemRootControllable {
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

extension AudioRootModel {
    public var exportControllable: any ExportControllable { exportController }
    public var importControllable: any ImportControllable { importController }
    public var gameControllable: any GameControllable { gameController }
    @MainActor public var itemControllable: any ItemControllable { itemController }
    public var searchControllable: any SearchControllable { searchController }
    public var audioGameControllable: any (GameControllable & AudioGameStorable) { gameController }
}

// MARK: - AudioPlayer

extension AudioRootModel {
    @MainActor
    public var audioCoordinatorPlayback: AudioListenerCoordinator? {
        audioController.prewarm()
        return audioController.model.coordinator
    }

    @MainActor
    public func listItems() -> [AudioModel] {
        itemController.itemDataModel.items.map {
            itemController.itemOrEmpty(for: $0)
        }
    }

    @MainActor public func itemDataCleanup() async throws {
        for itemId in itemController.itemDataModel.items {
            guard let model = await itemController.item(for: itemId) else { continue }
            if model.displayState == DisplayStateMask.totalHidden.rawValue {
                await editController.delete(itemId: model.id)
            }
        }
    }

    public func checkFolders(reportModel: ValidateRepairModel) async {
        let cc = ConvertController(itemController: itemController, editController: editController)
        await cc.repairHiddenAndFolders(reportModel: reportModel)
    }

    public func validateLinks(reportModel: ValidateRepairModel) async {
        await linkController.validateLinks(reportModel: reportModel)
    }
}
