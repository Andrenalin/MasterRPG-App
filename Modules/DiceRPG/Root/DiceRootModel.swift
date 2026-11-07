// @copyright André Trettin

import CoreRPG
import CoreData
import SwiftUI

@MainActor @Observable
public final class DiceRootModel {
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
        let linkController = LinkController(itemController: itemController, gameController: gameController)
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
            let controller = EntitySyncDataController(context: context, dataControllable: dataControllable, itemController: itemController, entity: RPGDice.entity())
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

    @ObservationIgnored var exportController: ExportController
    @ObservationIgnored var gameController: GameController
    @ObservationIgnored var importController: ImportController
    let itemController: ItemController
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

    @MainActor @ObservationIgnored let editorLinkModel: EditorLinkModel
    @MainActor @ObservationIgnored public let openFileWindowModel: OpenFileWindowModel
}

@MainActor
extension DiceRootModel: ItemRootControllable {
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

extension DiceRootModel {
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
    public var diceGameControllable: any (GameControllable & DiceGameStorable) {
        gameController
    }
}

// MARK: Game

public extension DiceRootModel {
    /// Rolls a dice set for the whole game and shares the result, as every dice button does:
    /// the roll, its share to the other players and the Siri donation.
    @MainActor
    internal func rollAndShare(diceId: UUID, networkActions: NetworkActions?, resultCategory: ResultCategory?) {
        gameController.rollDice(itemId: diceId, networkActions: networkActions, resultCategory: resultCategory)
#if !os(tvOS)
        donateRoll(of: diceId)
#endif
    }

    @MainActor
    func roll(diceId: UUID) -> Int {
        // Rolled on a copy and counted like a player's roll (reroll options, percent dice, the
        // per-die maximum, the modifier), not by adding the first face of each die. A table's
        // dice always add up. See CODE_AUDIT_22 §5.7.
        let dice = itemController.itemOrEmpty(for: diceId).copy(withId: UUID())
        dice.dice = dice.dice.map { $0.roll(resetResults: true, rerollOptions: dice.rerollOptions) }
        dice.sumUp = true
        return gameController.sumResult(of: dice)
    }

    func roll(number: Int) -> Int {
        RawDie(.number(number)).roll()
    }
}

