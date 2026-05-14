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
    }
    
    @MainActor public func setUp(context: NSManagedObjectContext?, batchContext: NSManagedObjectContext?, rootManager: RootManager, linkRegisterController: LinkRegisterController) {
        let dataController = context.map { DataController(context: $0, batchContext: batchContext, token: config.module.token) }
        _dataController = dataController
        let itemController = ItemController(config: config, tableRoot: tableRoot, dataController: dataController, linkRegisterController: linkRegisterController)
        _itemController = itemController
        _editController = EditController(root: self, itemController: itemController, linkRegisterController: linkRegisterController, tagController: searchModel.tagController)
        _exportController = ExportController(rootManager: rootManager, itemController: itemController)
        _importController = ImportController(itemController: itemController, editController: editController)
        _gameController = GameController(rootManager: rootManager, root: self, diceRoot: diceRoot, photoRoot: photoRoot, tableRoot: tableRoot, itemController: itemController, exportController: exportController)
        let linkController = LinkController(rootManager: rootManager, itemController: itemController, gameController: gameController)
        _linkController = linkController
        _searchController = SearchController(itemController: itemController)
        _sheetController = SheetController(itemController: itemController, linkController: linkController, linkRegisterController: linkRegisterController)
        
        _folderListController = FolderListController(listModel: FolderListModel(isSelectionMode: false, selection: [], navigationModel: navigationModel), listDisplayModel: listDisplayModel, searchModel: searchModel, itemControllable: itemController)

        _rootController = ItemRootController(
            config: config,
            listDisplayModel: listDisplayModel,
            searchModel: searchModel,
            navigationModel: navigationModel,
            inspectorEditorLinkModel: editorLinkModel,
            itemSelectionModel: itemSelectionModel,
            removeEntryListModel: removeEntryListModel,
            cacheControllable: nil,
            editControllable: editController,
            exportControllable: exportControllable,
            gameControllable: gameControllable,
            importControllable: importControllable,
            itemControllable: itemControllable,
            linkControllable: linkControllable,
            folderListControllable: folderListController,
            searchControllable: searchController,
            sheetControllable: sheetController,
            viewControllable: viewController
        )

        if let dataController, let context {
            _syncDataController = SyncDataController(context: context, dataController: dataController, editController: editController)
            Task {
                syncDataController?.start()
            }
        }
    }

    let diceRoot: DiceRootModel
    let pdfRoot: PdfRootModel
    let photoRoot: PhotoRootModel
    let tableRoot: TableRootModel

    public let config: ModuleConfiguration
    
    public let listDisplayModel: ListDisplayModel
    public let searchModel: SearchModel
    @ObservationIgnored public var itemSelectionModel: ItemSelectionModel
    @MainActor public var navigationModel: ModuleNavigationModel
    @ObservationIgnored public var linkSelectionModel: ItemSelectionModel
    
    @MainActor public var currentSelectedItemId: UUID? { folderListController.listModel.selectedItemId }
    public let removeEntryListModel = RemoveEntryListModel()
    
    @MainActor @ObservationIgnored lazy var editorLinkModel: EditorLinkModel = {
        EditorLinkModel(
            rootManager: RootManager(adventureRoot: self, audioRoot: self, characterRoot: self, diceRoot: diceRoot, generatorRoot: self, mapRoot: self, pdfRoot: pdfRoot, photoRoot: photoRoot, spaceRoot: self, tableRoot: tableRoot, weatherRoot: self),
            folderListController: folderListController.copy(parentModel: nil),
            characterSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: false, allowEntrySelection: true, onlyEntrySelection: true),
            diceSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false),
            pdfSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: true),
            photoSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false),
            tableSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: false, allowEntrySelection: true, onlyEntrySelection: true),
            firstRow: [.value, .dice, .pdf, .photo, .table],
            selection: .value
        )
    }()
    
    @ObservationIgnored private(set) var _dataController: DataController?
    var dataController: DataController? { _dataController }
    @ObservationIgnored private(set) var _syncDataController: SyncDataController?
    var syncDataController: SyncDataController? { _syncDataController }
    
    @ObservationIgnored private(set) var _itemController: ItemController?
    var itemController: ItemController { _itemController! }
    
    @ObservationIgnored private(set) var _editController: EditController?
    var editController: EditController { _editController! }
    @ObservationIgnored private(set) var _exportController: ExportController?
    var exportController: ExportController { _exportController! }
    @ObservationIgnored private(set) var _importController: ImportController?
    var importController: ImportController { _importController! }
    @ObservationIgnored private(set) var _gameController: GameController?
    var gameController: GameController { _gameController! }
    @ObservationIgnored private(set) var _linkController: LinkController?
    var linkController: LinkController { _linkController! }
    @ObservationIgnored private(set) var _searchController: SearchController?
    var searchController: SearchController { _searchController! }
    @ObservationIgnored private(set) var _sheetController: SheetController?
    var sheetController: SheetController { _sheetController! }

    @ObservationIgnored private(set) var _folderListController: FolderListController?
    var folderListController: FolderListControllable { _folderListController! }

    @MainActor @ObservationIgnored var folderLinkController: FolderListControllable {
        rootController.folderLinkControllable
    }

    @ObservationIgnored public lazy var viewController: ViewController = {
        ViewController()
    }()

    @MainActor @ObservationIgnored private(set) var _rootController: ItemRootController?
    @MainActor public var rootController: ItemRootController { _rootController!}
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
                editController.delete(itemId: model.id)
            }
        }
    }
    
    public func checkFolders(reportModel: ValidateRepairModel) async {
        reportModel.update(section: "Validating Character Data")
        for id in itemController.itemDataModel.items {
            guard let model = await itemController.item(for: id), model.specialCategory == false else { continue }
            var entries: [ValueEntryModel] = []
            for entry in model.entries {
                guard let valueId = entry.valueId, let value = await itemController.item(for: valueId) else {
                    entries.append(entry)
                    continue
                }
                if let valueItem = editController.editModel(for: valueId) {
                    valueItem.parentId <=> model.id
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
}
