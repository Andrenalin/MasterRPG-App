// @copyright André Trettin

import CoreRPG
import DiceRPG
import PdfRPG
import PhotoRPG
import TableRPG
import CoreData
import SwiftData
import SwiftUI

@MainActor @Observable
public final class CharacterRootModel {
    @MainActor init(tagController: TagController, diceRoot: DiceRootModel, pdfRoot: PdfRootModel, photoRoot: PhotoRootModel, tableRoot: TableRootModel) {
        self.diceRoot = diceRoot
        self.pdfRoot = pdfRoot
        self.photoRoot = photoRoot
        self.tableRoot = tableRoot

        let config = ModuleConfiguration()
        self.config = config

        let listDisplayModel = ListDisplayModel()
        self.listDisplayModel = listDisplayModel
        let searchModel = SearchModel(tagController: tagController, module: config.module, categoryTags: config.categoryTags)
        self.searchModel = searchModel

        self.itemSelectionModel = ItemSelectionModel()
        self.navigationModel = ModuleNavigationModel()
        self.linkSelectionModel = config.linkSelectionModel

        self.itemController = ItemController(config: config, tableRoot: tableRoot)
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

        _linkController = LinkController(root: self, diceRoot: diceRoot, photoRoot: photoRoot, tableRoot: tableRoot, itemController: itemController)
        _sheetController = SheetController(itemController: itemController, linkController: linkController)
        _editController = EditController(root: self, itemController: itemController, linkController: linkController, sheetController: sheetController, tagController: searchModel.tagController)
        _exportController = ExportController(hubControllable: adventureRootControllable, diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot, itemController: itemController)
        _gameController = GameController(root: self, diceRoot: diceRoot, photoRoot: photoRoot, tableRoot: tableRoot, itemController: itemController, exportController: exportController)

        syncTask?.cancel()
        if let dataControllable = itemController.itemDataModel.dataController, let context {
            let controller = SyncDataController(context: context, dataControllable: dataControllable, itemController: itemController)
            syncDataController = controller
            syncTask = controller.start()
        }
    }

    let diceRoot: DiceRootModel
    let pdfRoot: PdfRootModel
    let photoRoot: PhotoRootModel
    let tableRoot: TableRootModel

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
            rootManager: RootManager(adventureRoot: self, audioRoot: self, characterRoot: self, diceRoot: diceRoot, generatorRoot: self, mapRoot: self, pdfRoot: pdfRoot, photoRoot: photoRoot, spaceRoot: self, tableRoot: tableRoot, weatherRoot: self),
            folderListController: folderLinkController,
            characterSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: false, allowEntrySelection: true, onlyEntrySelection: true),
            diceSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false),
            pdfSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: true),
            photoSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false),
            tableSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: false, allowEntrySelection: true, onlyEntrySelection: true),
            firstRow: [.value, .dice, .pdf, .photo, .table],
            selection: .value
        )
    }()

    @MainActor @ObservationIgnored lazy public var openFileWindowModel: OpenFileWindowModel = { OpenFileWindowModel(windowId: NetworkModules.value.viewerWindowId, canShow: true) { DetailRoute.viewer($0) }
    }()

    @ObservationIgnored var syncDataController: SyncDataController?
    @ObservationIgnored var syncTask: Task<Void, Never>?

    let itemController: ItemController
    @ObservationIgnored private var _linkController: LinkController?
    var linkController: LinkController { _linkController! }
    @ObservationIgnored private var _sheetController: SheetController?
    var sheetController: SheetController { _sheetController! }
    @ObservationIgnored private var _editController: EditController?
    var editController: EditController { _editController! }
    @ObservationIgnored private var _exportController: ExportController?
    var exportController: ExportController { _exportController! }
    @ObservationIgnored private var _importController: ImportController?
    var importController: ImportController {
        if let controller = _importController { return controller }
        let controller = ImportController(itemController: itemController, editController: editController)
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
        _rootController = controller
        return controller
    }
}

@MainActor
extension CharacterRootModel: ItemRootControllable {
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

// MARK: - Actions

extension CharacterRootModel {
    @MainActor
    public var valueActions: ValueActions {
        ValueActions(addResult: gameController.add(result:for:), createModelResult: gameController.create(name:description:entries:resultCategory:), createEntryResult: gameController.create(name:value:resultCategory:))
    }

    @MainActor
    public func listItems() -> [ValueModel] {
        itemController.itemDataModel.items.map {
            itemController.itemOrEmpty(for: $0)
        }
    }

    public func itemDataCleanup() async throws {
        for itemId in itemController.itemDataModel.items {
            guard let model = await itemController.item(for: itemId) else { continue }
            if model.displayState == 2 {
                await editController.delete(itemId: model.id)
            }
        }
    }

    public func checkFolders(reportModel: ValidateRepairModel) async {
        reportModel.update(section: "Validating Character Data")
        editController.repairCharacterContrains()

        for id in itemController.itemDataModel.items {
            guard let model = await itemController.item(for: id), model.displayState != 2 && model.specialCategory == false else { continue }
            var entries: [ValueEntryModel] = []
            for entry in model.entries {
                guard let valueId = entry.valueId, let value = await itemController.item(for: valueId) else {
                    entries.append(entry)
                    continue
                }
                if let valueItem = editController.editModel(for: valueId) {
                    valueItem.groupId <=> model.id
                    // Only clear parentId if it was used as the group reference (Phase 2 data).
                    // A real folder parentId (pointing to a folder, not the group owner) must be kept.
                    if valueItem.parentId == model.id {
                        valueItem.parentId = nil
                    }
                    valueItem.displayState <=> 1
                    editController.save(updated: valueItem, message: String(localized: "Repaired Subvalues", bundle: .module).localizedString)
                }

                editController.reset(tags: [], itemId: valueId)
                await editController.removePhotos(itemId: valueId)

                if entry.name != value.name {
                    var updatedEntry = entry
                    updatedEntry.name = value.name.withoutLink()
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
