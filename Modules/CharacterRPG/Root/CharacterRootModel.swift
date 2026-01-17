// @copyright André Trettin

import CoreRPG
import DiceRPG
import PdfRPG
import PhotoRPG
import TableRPG
import CoreData
import SwiftData
import SwiftUI

@Observable
public final class CharacterRootModel: @unchecked Sendable {
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
        self.linkSelectionModel = config.linkSelectionModel
    }
    
    @MainActor public func setUp(context: NSManagedObjectContext?, rootControllable: RootControllable) {
        self._rootControllable = rootControllable
        
        let dataController = context.map { DataController(context: $0, token: config.module.token) }
        _dataController = dataController
        let itemController = ItemController(config: config, tableRoot: tableRoot, dataController: dataController, linkRegisterControllable: rootControllable.linkRegisterControllable)
        _itemController = itemController
        _editController = EditController(root: self, diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot, itemController: itemController, linkRegisterControllable: rootControllable.linkRegisterControllable, tagController: searchModel.tagController)
        _exportController = ExportController(diceRoot: diceRoot, photoRoot: photoRoot, tableRoot: tableRoot, itemController: itemController, gameExporter: false)
        _importController = ImportController(itemController: itemController)
        _gameController = GameController(root: self, diceRoot: diceRoot, photoRoot: photoRoot, tableRoot: tableRoot, itemController: itemController, linkRegisterControllable: rootControllable.linkRegisterControllable, rootExportControllable: rootControllable.gameExportControllable, rootImportControllable: rootControllable.gameImportControllable)
        _linkController = LinkController(root: self, diceRoot: diceRoot, photoRoot: photoRoot, tableRoot: tableRoot, itemController: itemController, gameController: gameController)

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
    public var itemSelectionModel: ItemSelectionModel
    public var linkSelectionModel: ItemSelectionModel
    
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
            firstRow: [.value, .dice, .pdf, .table],
            selection: .value
        )
    }()
    
    @ObservationIgnored private(set) var _dataController: DataController?
    var dataController: DataController? { _dataController }
    @ObservationIgnored private(set) var _syncDataController: SyncDataController?
    var syncDataController: SyncDataController? { _syncDataController }
    
    @ObservationIgnored private(set) var _itemController: ItemController?
    var itemController: ItemController { _itemController.unsafelyUnwrapped }
    
    @ObservationIgnored private(set) var _editController: EditController?
    var editController: EditController { _editController.unsafelyUnwrapped }
    @ObservationIgnored private(set) var _exportController: ExportController?
    var exportController: ExportController { _exportController.unsafelyUnwrapped }
    @ObservationIgnored private(set) var _importController: ImportController?
    var importController: ImportController { _importController.unsafelyUnwrapped }
    @ObservationIgnored private(set) var _gameController: GameController?
    var gameController: GameController { _gameController.unsafelyUnwrapped }
    @ObservationIgnored private(set) var _linkController: LinkController?
    public var linkController: LinkController { _linkController.unsafelyUnwrapped }
    
    @MainActor @ObservationIgnored lazy var folderListController: FolderListControllable = {
        FolderListController(listModel: FolderListModel(isSelectionMode: false, selection: []), listDisplayModel: listDisplayModel, searchModel: searchModel, itemControllable: itemController)
    }()
    @MainActor @ObservationIgnored var folderLinkController: FolderListControllable {
        rootController.folderLinkControllable
    }

    @ObservationIgnored public lazy var viewController: ViewController = {
        ViewController()
    }()

    @ObservationIgnored private(set) var _rootControllable: RootControllable?
    var rootControllable: RootControllable { _rootControllable.unsafelyUnwrapped }
    
    @MainActor @ObservationIgnored public lazy var rootController: ItemRootController = {
        ItemRootController(
            config: config,
            listDisplayModel: listDisplayModel,
            searchModel: searchModel,
            itemSelectionModel: itemSelectionModel,
            removeEntryListModel: removeEntryListModel,
            cacheControllable: nil,
            editControllable: editController,
            exportControllable: exportControllable,
            gameControllable: gameControllable,
            itemControllable: itemControllable,
            linkControllable: rootControllable.linkControllable,
            folderListControllable: folderListController,
            viewControllable: viewController
        )
    }()
}

extension CharacterRootModel: ItemRootControllable {
    public var configurable: any ModuleConfigurable { config }
    public var cacheControllable: (any ImageCacheControllable)? { nil }
    public var editControllable: any EditControllable { editController }
    public var folderListControllable: any FolderListControllable { folderListController }
    public var folderLinkControllable: any FolderListControllable { folderLinkController }
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
        for itemId in await itemController.itemDataModel.items {
            guard let model = await itemController.item(for: itemId) else { continue }
            if model.displayState == 2 {
                await editController.delete(itemId: model.id)
            }
        }
    }
    
    public func checkFolders() async {
        for id in await itemController.itemDataModel.items {
            guard let model = await itemController.item(for: id) else { continue  }
            var entries: [ValueEntryModel] = []
            for entry in model.entries {
                guard let valueId = entry.valueId, let value = await itemController.item(for: valueId) else {
                    entries.append(entry)
                    continue
                }
                await editController.addItem(itemId: valueId, parentId: model.id)
                await editController.reset(tags: [], itemId: valueId)
                await editController.removePhotos(itemId: valueId)
                
                if entry.name != value.name {
                    var updatedEntry = entry
                    updatedEntry.name = value.name.withoutLink()
                    updatedEntry.content = value.description
                    entries.append(updatedEntry)
                }
            }
            if model.entries != entries {
                guard let item = await editController.editModel(for: id) else { continue }
                item.entries <=> entries
                await editController.save(updated: item, message: String(localized: "update entries").localizedString)
            }
            guard model.diceId == nil else { continue }
            let entry = model.entries.first {
                $0.diceId != nil
            }
            await editController.add(diceId: entry?.diceId, itemId: model.id)
        }

        let cc = ConvertController(itemController: itemController, editController: editController)
        await cc.createFoldersAndCollections(excludeHidden: true)
    }
}

public extension CharacterRootModel {
    @MainActor
    func addNewValue(name: String, text: String, photoIds: [UUID]) async {
        let itemId = await itemController.addNew(type: .item)
        editController.reset(name: name, itemId: itemId)
        editController.reset(description: text, itemId: itemId)
        //editController.add(photoId: photoId, itemId: itemId)
    }

    @MainActor
    func sheet(for itemId: UUID, level: Int = 0) -> SheetModel {
        SheetController(itemController: itemController, linkController: linkController).sheet(for: itemId, level: level)
    }
}
