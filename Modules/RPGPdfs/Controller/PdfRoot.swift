// @copyright André Trettin

import AndrenalinKit
import CoreData
import SwiftData
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor @Observable
public final class RootModel: Sendable {
    
    @MainActor
    public var selectedItem: ItemRowModel?
    @MainActor
    public var gameItemSelection: ItemRowModel?
    
    @ObservationIgnored
    var listModels: [UUID: ListModel] = [:]
}

@Observable
public final class PdfRoot: @unchecked Sendable {
    @MainActor
    init(container: ModelContainer) {
        rootModel = RootModel()
        let module: NetworkModules = .pdf
        self.module = module
        
        let listDisplayModel = ListDisplayModel()
        self.listDisplayModel = listDisplayModel
        let searchModel = SearchModel(modelContainer: container, module: module, categoryTags: [.adventure, .character, .rules, .supplement])
        self.searchModel = searchModel
        
        let itemSelectionModel = ItemSelectionModel()
        self.itemSelectionModel = itemSelectionModel
    }
    
    @MainActor public func setUp(context: NSManagedObjectContext?, rootControllable: RootControllable) {
        self._rootControllable = rootControllable
                
        let dataController = context.map { DataController(context: $0, token: module.token) }
        _dataController = dataController
        let itemController = ItemController(dataController: dataController, linkRegisterControllable: rootControllable.linkRegisterControllable)
        _itemController = itemController
        _editControllers = [EditTypes.main: EditController(itemController: itemController, linkRegisterControllable: linkRegisterControllable, currentListItem: nil, currentModel: nil)]
        _exportController = ExportController(itemController: itemController, gameExporter: false)
        _importController = ImportController(itemController: itemController)
        _gameController = GameController(itemController: itemController, linkRegisterControllable: rootControllable.linkRegisterControllable, rootExportControllable: rootControllable.gameExportControllable, rootImportControllable: rootControllable.gameImportControllable)
        _linkController = LinkController(itemController: itemController, gameController: gameController)

        if let dataController, let context {
            _syncDataController = SyncDataController(context: context, dataController: dataController, itemController: itemController)
            Task {
                syncDataController?.start()
            }
        }
    }

    public let rootModel: RootModel
    public let module: NetworkModules
    
    public let listDisplayModel: ListDisplayModel
    public let searchModel: SearchModel
    public var itemSelectionModel: ItemSelectionModel
    @MainActor public var currentSelectedItemId: UUID? { folderListController.listModel.selectedItemId }
        
    public let removeEntryListModel = RemoveEntryListModel()
    
    var cacheController: CacheController? { itemController.cacheController }
    @ObservationIgnored private(set) var _dataController: DataController?
    var dataController: DataController? { _dataController }
    public var fileUrlDataController: FileUrlDataController? { itemController.fileUrlDataController }
    @ObservationIgnored private(set) var _syncDataController: SyncDataController?
    var syncDataController: SyncDataController? { _syncDataController }
    
    @ObservationIgnored private(set) var _itemController: ItemController?
    var itemController: ItemController { _itemController.unsafelyUnwrapped }
    
    @ObservationIgnored private var _editControllers: [EditTypes: EditController] = [:]
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
    @MainActor @ObservationIgnored lazy var folderLinkController: FolderListControllable = {
        folderListController.copy(parentModel: nil)
    }()
    @ObservationIgnored public lazy var viewController: ViewController = {
        ViewController()
    }()

    
    @ObservationIgnored private(set) var _rootControllable: RootControllable?
    var rootControllable: RootControllable { _rootControllable.unsafelyUnwrapped }
    
    @ObservationIgnored private(set) var mainListController: ListController?

    @MainActor @ObservationIgnored public lazy var rootController: ItemRootController = {
        ItemRootController(
            module: module,
            listDisplayModel: listDisplayModel,
            searchModel: searchModel,
            itemSelectionModel: ItemSelectionModel(),
            removeEntryListModel: RemoveEntryListModel(),
            cacheControllable: cacheController,
            editControllable: editController(type: .main),
            exportControllable: exportControllable,
            gameControllable: gameControllable,
            itemControllable: itemControllable,
            linkControllable: linkControllable,
            listControllable: listController,
            folderListControllable: folderListController,
            viewControllable: viewController
        )
    }()
}

extension PdfRoot: ItemRootControllable {
    public var cacheControllable: (any ImageCacheControllable)? { cacheController }
    public var editControllable: any EditControllable { editController(type: .main) }
    public var listControllable: any ListControllable { listController }
    public var folderListControllable: any FolderListControllable { folderListController }
    public var folderLinkControllable: any FolderListControllable { folderLinkController }
    public var viewControllable: any ViewControllable { viewController }
}

extension PdfRoot {
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

    func applyToAllEditController(handler: @escaping @Sendable (EditController) async -> Void) async {
        for editController in _editControllers.values {
            await handler(editController)
        }
    }

    @MainActor
    func editController(for item: ItemRowTreeModel? = nil, type: EditTypes) -> EditController {
        guard let oldEditController = _editControllers[type] else {
            let model = item.map { itemController.itemOrEmpty(for: $0.model.itemId) }
            let newEditController = EditController(itemController: itemController, linkRegisterControllable: linkRegisterControllable, currentListItem: item, currentModel: model)
            _editControllers[type] = newEditController
            return newEditController
        }
        return oldEditController
    }

    @MainActor
    private var listController: ListController {
        ListController(itemController: itemController, listStoreName: "Pdf", hasChildren: true, searchToken: .all, categoryTags: itemController.itemDataModel.categoryTags)
    }
    func listController(model: ListModel) -> ListController {
        ListController(itemController: itemController, itemListModel: model)
    }
    @MainActor
    func listController(tabId: UUID, focus: ItemRowModel? = nil) -> ListController {
        guard let listModel = rootModel.listModels[tabId] else {
            let newController = listController
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
    private func setMainListController(_ listController: ListController) {
        guard mainListController == nil else { return }
        mainListController = listController
    }

    public static let thumbnailSize: CGSize = .init(width: 64.0, height: 64.0)
    
    public func moveFiles() async throws {
        func moveFiles() async throws {
            let itemIds = await itemController.itemDataModel.items
            for itemId in itemIds {
                let item = await itemController.itemOrEmpty(for: itemId)
                guard let fileUrl = item.fileUrl, fileUrl.location != .newCloud else { continue }
                if let newFileUrl = try? await fileUrlDataController?.move(fileUrl: fileUrl, name: item.name, category: item.category.title) {
                    let editController = await editController(type: .main)
                    await editController.reset(fileUrl: newFileUrl, for: itemId)
                }
            }
        }
    }
    
    @MainActor
    public func listItems() -> [PdfModel] {
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
        let cc = await ConvertController(itemController: itemController, editController: editController(type: .main))
        await cc.checkFolders()
    }
}
