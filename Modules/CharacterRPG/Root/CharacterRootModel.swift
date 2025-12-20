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
public final class RootModel: Sendable {
    
    @MainActor
    public var selectedItem: ItemRowModel?
    @MainActor
    public var gameItemSelection: ItemRowModel?

    @ObservationIgnored
    var listModels: [UUID: ListModel] = [:]

    @MainActor
    var generatorItemId: UUID = UUID()
    
    @MainActor
    private(set) var generatorController: GeneratorController?
    
    @MainActor
    func resetGeneratorController(rootItem: ItemRowModel?, generatorController: GeneratorController) {
        let newRootId = rootItem?.itemId ?? UUID()
        if newRootId == generatorItemId {
            generatorItemId = UUID()
        }
        generatorItemId = newRootId
        self.generatorController = generatorController
    }
}

@Observable
public final class CharacterRootModel: @unchecked Sendable {
    @MainActor init(container: ModelContainer, diceRoot: DiceRootModel, pdfRoot: PdfRootModel, photoRoot: PhotoRootModel, tableRoot: TableRootModel) {
        self.diceRoot = diceRoot
        self.pdfRoot = pdfRoot
        self.photoRoot = photoRoot
        self.tableRoot = tableRoot

        rootModel = RootModel()
        
        let module: NetworkModules = .value
        self.module = module
        
        let listDisplayModel = ListDisplayModel()
        self.listDisplayModel = listDisplayModel
        let searchModel = SearchModel(modelContainer: container, module: module, categoryTags: [.building, .item, .supplement])
        self.searchModel = searchModel
        
        self.itemSelectionModel = ItemSelectionModel()
        self.linkSelectionModel = ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: true)
    }
    
    @MainActor public func setUp(context: NSManagedObjectContext?, rootControllable: RootControllable) {
        self._rootControllable = rootControllable
        
        let dataController = context.map { DataController(context: $0, token: module.token) }
        _dataController = dataController
        let itemController = ItemController(tableRoot: tableRoot, dataController: dataController, linkRegisterControllable: rootControllable.linkRegisterControllable)
        _itemController = itemController
        _editController = EditController(root: self, diceRoot: diceRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, tableRoot: tableRoot, itemController: itemController, linkRegisterControllable: rootControllable.linkRegisterControllable, currentListItem: nil, currentModel: nil)
        _exportController = ExportController(diceRoot: diceRoot, photoRoot: photoRoot, tableRoot: tableRoot, itemController: itemController, gameExporter: false)
        _importController = ImportController(itemController: itemController)
        _gameController = GameController(root: self, diceRoot: diceRoot, photoRoot: photoRoot, tableRoot: tableRoot, itemController: itemController, linkRegisterControllable: rootControllable.linkRegisterControllable, rootExportControllable: rootControllable.gameExportControllable, rootImportControllable: rootControllable.gameImportControllable)
        _linkController = LinkController(root: self, diceRoot: diceRoot, photoRoot: photoRoot, tableRoot: tableRoot, itemController: itemController, gameController: gameController)

        if let dataController, let context {
            _syncDataController = SyncDataController(context: context, dataController: dataController, itemController: itemController)
            Task {
                syncDataController?.start()
            }
        }
    }

    let diceRoot: DiceRootModel
    let pdfRoot: PdfRootModel
    let photoRoot: PhotoRootModel
    let tableRoot: TableRootModel

    public let rootModel: RootModel
    public let module: NetworkModules
    
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
            characterSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: true),
            diceSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false),
            pdfSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false),
            photoSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: false),
            tableSelectionModel: ItemSelectionModel(selection: [], isSingleSelection: false, allowCollections: true, allowEntrySelection: true),
            firstRow: [.value, .table, .dice, .pdf],
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
    
    @ObservationIgnored
    private(set) var mainListController: ListController?
    
    @MainActor @ObservationIgnored public lazy var rootController: ItemRootController = {
        ItemRootController(
            module: module,
            listDisplayModel: listDisplayModel,
            searchModel: searchModel,
            itemSelectionModel: ItemSelectionModel(),
            removeEntryListModel: RemoveEntryListModel(),
            cacheControllable: nil,
            editControllable: editController,
            exportControllable: exportControllable,
            gameControllable: gameControllable,
            itemControllable: itemControllable,
            linkControllable: rootControllable.linkControllable,
            listControllable: listController,
            folderListControllable: folderListController,
            viewControllable: viewController
        )
    }()
}

extension CharacterRootModel: ItemRootControllable {
    public var cacheControllable: (any ImageCacheControllable)? { nil }
    public var editControllable: any EditControllable { editController }
    public var listControllable: any ListControllable { listController }
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
    public var valueGameControllable: any (GameControllable & ValueGameStorable) {
        gameController
    }
    public var itemControllable: any ItemControllable {
        itemController
    }
    
    @MainActor
    private var listController: ListController {
        ListController(itemController: itemController, editController: editController, listStoreName: "Characters", hasChildren: true, searchToken: .all, categoryTags: itemController.itemDataModel.categoryTags)
    }
    func listController(model: ListModel) -> ListController {
        ListController(itemController: itemController, editController: editController, itemListModel: model)
    }
    @MainActor
    func listController(tabId: UUID, config: Bool = false, focus: ItemRowModel? = nil) -> ListController {
        guard let listModel = rootModel.listModels[tabId] else {
            let newController = listController
            if config {
                newController.model.categoryTags.removeAll(where: { $0 == .gameMaster })
                newController.model.hideChildrenHeader = true
            }
            newController.update(models: itemController.itemDataModel.items.map { ItemRowModel(itemId: $0, typeId: itemController.itemDataModel.networkModule) })
            if let focus {
                newController.setFocusItem(model: focus)
            }
            setMainListController(newController)
            rootModel.listModels[tabId] = newController.model
            return newController
        }
        return listController(model: listModel)
    }

    @MainActor
    func generatorController(rootItem: ItemRowModel?, saveId: UUID?) -> GeneratorController {
        GeneratorController(root: self, rootItemId: rootItem?.itemId ?? UUID(), saveId: saveId)
    }
    
    @MainActor
    func resetGeneratorController(rootItem: ItemRowModel?, saveId: UUID?) {
        rootModel.resetGeneratorController(rootItem: rootItem, generatorController: generatorController(rootItem: rootItem, saveId: saveId))
    }
    
    @MainActor
    private func setMainListController(_ listController: ListController) {
        guard mainListController == nil else { return }
        mainListController = listController
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
                await itemController.delete(itemId: model.id)
            }
        }
    }
    
    public func checkFolders() async {
        let cc = ConvertController(itemController: itemController, editController: editController)
        await cc.createFoldersAndCollections(excludeHidden: true)
    }
}

public extension CharacterRootModel {
    @MainActor
    func addNewValue(name: String, text: String, photoIds: [UUID]) async {
        let itemRowModel = await itemController.addNew(type: nil)
        let editController = editController
        editController.setCurrentItem(to: ItemRowTreeModel(id: UUID(), model: itemRowModel))
        editController.model.name = name
        editController.model.description = text
        editController.model.photos = photoIds
        editController.model.photoId = photoIds.first
        editController.save(with: String(localized: "Create new").localizedString)
    }

    @MainActor
    func sheet(for itemId: UUID, level: Int = 0) -> SheetModel {
        SheetController(itemController: itemController, linkController: linkController).sheet(for: itemId, level: level)
    }
}
