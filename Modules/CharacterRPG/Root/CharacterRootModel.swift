// @copyright André Trettin

import CoreRPG
import DiceRPG
#if !os(tvOS)
import GeneratorRPG
#endif
import PdfRPG
import PhotoRPG
import TableRPG
import CoreData
import SwiftUI

@MainActor @Observable
public final class CharacterRootModel {
    @MainActor init(tagController: TagController, diceRoot: DiceRootModel, generatorRoot: GeneratorRootModel? = nil, pdfRoot: PdfRootModel, photoRoot: PhotoRootModel, tableRoot: TableRootModel) {
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
        self.photoRoot = photoRoot
        self.tableRoot = tableRoot

        let itemController = ItemController(config: config)
        self.itemController = itemController
        self.exportController = ExportController(diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot, itemController: itemController)
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
            characterSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: false, allowEntrySelection: true, onlyEntrySelection: true),
            diceSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false),
            pdfSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: true),
            photoSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false),
            tableSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: false, allowEntrySelection: true, onlyEntrySelection: true),
            firstRow: [.value, .dice, .pdf, .photo, .table],
            selection: .value
        )
        self.openFileWindowModel = OpenFileWindowModel(windowId: NetworkModules.value.viewerWindowId, canShow: true) { DetailRoute.viewer($0) }
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
        // `gameSheetRootModel` (the live game view's persistent counterpart) is
        // deliberately not created here — it only exists while an actual game
        // view is on screen. See `ViewerRootView.gameSheetRootModel`, which
        // creates and stores it lazily, and `GameController.resetGameState()`,
        // which clears it again when the game ends.
        editorLinkModel.rootManager = rootManager

        syncTask?.cancel()
        if let dataControllable = itemController.itemDataModel.dataController, let context {
            let controller = SyncDataController(context: context, dataControllable: dataControllable, itemController: itemController)
            syncDataController = controller
            syncTask = controller.start()
        }
    }

    let diceRoot: DiceRootModel
    let generatorRoot: GeneratorRootModel?
    let pdfRoot: PdfRootModel
    let photoRoot: PhotoRootModel
    let tableRoot: TableRootModel

    public let config: ModuleConfiguration
    @MainActor public var navigationModel: ModuleNavigationModel
    @ObservationIgnored public var itemSelectionModel: ItemSelectionModel
    @ObservationIgnored public var linkSelectionModel: ItemSelectionModel
    public let removeEntryListModel: RemoveEntryListModel

    public let listDisplayModel: ListDisplayModel
    let searchModel: SearchModel

    let itemController: ItemController
    @ObservationIgnored lazy var linkController: LinkController = {
        LinkController(root: self, diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot, itemController: itemController)
    }()
    @ObservationIgnored lazy var sheetController: SheetController = {
        SheetController(itemController: itemController, linkController: linkController)
    }()
    @ObservationIgnored lazy var editController: EditController = {
        EditController(root: self, itemController: itemController, tagController: searchModel.tagController)
    }()
    @ObservationIgnored var exportController: ExportController
    @ObservationIgnored lazy var gameController: GameController = {
        GameController(root: self, diceRoot: diceRoot, photoRoot: photoRoot, tableRoot: tableRoot, itemController: itemController, exportController: exportController)
    }()
    @ObservationIgnored lazy var importController: ImportController = {
        ImportController(itemController: itemController, editController: editController)
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
    @MainActor @ObservationIgnored public let openFileWindowModel: OpenFileWindowModel
}

@MainActor
extension CharacterRootModel: ItemRootControllable {
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

extension CharacterRootModel {
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
    public var valueGameControllable: any (GameControllable & ValueGameStorable) {
        gameController
    }
}

// MARK: - Game Sheet

extension CharacterRootModel {
    /// Eagerly resolves (creating if needed) the live game view's persistent
    /// sheet slot for `itemId`, so `ReaderSheetView` finds it already in place
    /// when the character panel first renders instead of racing its own
    /// `onChange`-driven lazy creation. Called once at game join — see
    /// `GameController.startGame(for:)`. Cleared again in
    /// `GameController.resetGameState()` when the game ends.
    @MainActor func startGameSheetRootModel(itemId: UUID) {
        if let existing = editController.editorModel.gameSheetRootModel {
            existing.reset(itemId: itemId)
            return
        }
        guard let rootManager else { return }
        editController.editorModel.gameSheetRootModel = SheetRootModel(
            rootManager: rootManager,
            linkControllable: rootController.linkControllable,
            sheetControllable: rootController.sheetControllable,
            itemId: itemId,
            isEditor: false,
            isGameEditor: true
        )
    }
}

// MARK: - Actions

extension CharacterRootModel {
    public func itemDataCleanup() async throws {
        for itemId in itemController.itemDataModel.items {
            guard let model = await itemController.item(for: itemId) else { continue }
            if model.displayState == DisplayStateMask.totalHidden.rawValue {
                await editController.delete(itemId: model.id)
            }
        }
    }

    public func checkFolders(reportModel: ValidateRepairModel) async {
        reportModel.update(section: "Validating Character Data")
        editController.repairCharacterConstraints()

        for id in itemController.itemDataModel.items {
            guard let model = await itemController.item(for: id), model.displayState != DisplayStateMask.totalHidden.rawValue && model.specialCategory == false else { continue }
            var entries: [ValueEntryModel] = []
            for entry in model.entries {
                guard let valueId = entry.valueId, let value = await itemController.item(for: valueId) else {
                    entries.append(entry)
                    continue
                }
                if let valueItem = editController.editModel(for: valueId) {
                    let before = (valueItem.groupId, valueItem.parentId, valueItem.displayState)
                    valueItem.groupId <=> model.id
                    // Only clear parentId if it was used as the group reference (Phase 2 data).
                    // A real folder parentId (pointing to a folder, not the group owner) must be kept.
                    if valueItem.parentId == model.id {
                        valueItem.parentId = nil
                    }
                    valueItem.displayState <=> 1
                    // Only a changed group item is saved, so a repair run does not move the sync
                    // clocks of unchanged data. See CODE_AUDIT_23 §5.21.
                    if (valueItem.groupId, valueItem.parentId, valueItem.displayState) != before {
                        editController.save(updated: valueItem, message: String(localized: "Repaired Subvalues", bundle: .module).localizedString)
                    }
                }

                if !value.tags.isEmpty {
                    editController.reset(tags: [], itemId: valueId)
                }
                if value.photoId != nil || !value.photos.isEmpty {
                    await editController.removePhotos(itemId: valueId)
                }

                // The entry shows the group item's name as plain text. Comparing it with the raw name
                // (a markdown link for table-generated items) never matches what is written here,
                // so every repair rewrote the entry and moved its sync clock.
                let linkFreeName = value.name.withoutLink()
                if entry.name != linkFreeName {
                    var updatedEntry = entry
                    updatedEntry.name = linkFreeName
                    updatedEntry.content = value.description
                    entries.append(updatedEntry)
                } else {
                    entries.append(entry)
                }
            }
            if model.entries != entries {
                guard let item = editController.editModel(for: id) else { continue }
                item.entries = entries
                editController.save(updated: item, message: String(localized: "update entries", bundle: .module).localizedString)
            }
            guard model.diceId == nil else { continue }
            let entry = model.entries.first {
                $0.diceId != nil
            }
            editController.add(diceId: entry?.diceId, itemId: model.id)
        }

        let cc = ConvertController(itemController: itemController, editController: editController)
        await cc.repairHiddenAndFolders(reportModel: reportModel)
    }

    public func validateLinks(reportModel: ValidateRepairModel) async {
        await linkController.validateLinks(reportModel: reportModel)
    }
}
