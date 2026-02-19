// @copyright André Trettin

import CoreRPG
import CoreData
import SwiftData
import SwiftUI

@Observable
public final class PhotoRootModel: @unchecked Sendable {    
    @MainActor init(tagController: TagController) {
        let config = ModuleConfiguration()
        self.config = config
        
        let listDisplayModel = ListDisplayModel()
        self.listDisplayModel = listDisplayModel
        let searchModel = SearchModel(tagController: tagController, module: config.module, categoryTags: config.categoryTags)
        self.searchModel = searchModel
        
        self.itemSelectionModel = ItemSelectionModel()
        self.linkSelectionModel = config.linkSelectionModel
    }
    
    @MainActor public func setUp(context: NSManagedObjectContext?, batchContext: NSManagedObjectContext?, rootManager: RootManager, linkRegisterController: LinkRegisterController) {
        let dataController = context.map { DataController(context: $0, batchContext: batchContext, token: config.module.token) }
        _dataController = dataController
        let itemController = ItemController(config: config, dataController: dataController, linkRegisterController: linkRegisterController)
        _itemController = itemController
        _editController = EditController(itemController: itemController, linkRegisterController: linkRegisterController, tagController: searchModel.tagController)
        _exportController = ExportController(rootManager: rootManager, itemController: itemController)
        _importController = ImportController(itemController: itemController)
        _gameController = GameController(rootManager: rootManager, itemController: itemController, exportController: exportController)
        _linkController = LinkController(rootManager: rootManager, itemController: itemController, gameController: gameController)

        _folderListController = FolderListController(listModel: FolderListModel(isSelectionMode: false, selection: []), listDisplayModel: listDisplayModel, searchModel: searchModel, itemControllable: itemController)

        _rootController = ItemRootController(
            config: config,
            listDisplayModel: listDisplayModel,
            searchModel: searchModel,
            itemSelectionModel: itemSelectionModel,
            removeEntryListModel: removeEntryListModel,
            cacheControllable: cacheController,
            editControllable: editController,
            exportControllable: exportControllable,
            gameControllable: gameControllable,
            importControllable: importControllable,
            itemControllable: itemControllable,
            linkControllable: linkControllable,
            folderListControllable: folderListController,
            viewControllable: viewController
        )

        if let dataController, let context {
            _syncDataController = SyncDataController(context: context, dataController: dataController, editController: editController)
            Task {
                Task {
                syncDataController?.start()
            }
            }
        }
    }

    public let config: ModuleConfiguration
    
    public let listDisplayModel: ListDisplayModel
    public let searchModel: SearchModel
    public var itemSelectionModel: ItemSelectionModel
    public var linkSelectionModel: ItemSelectionModel
    
    @MainActor public var currentSelectedItemId: UUID? { folderListController.listModel.selectedItemId }
    public let removeEntryListModel = RemoveEntryListModel()
    
    var cacheController: CacheController? { itemController.cacheController }
    @ObservationIgnored private(set) var _dataController: DataController?
    var dataController: DataController? { _dataController }
    public var fileUrlDataController: FileUrlDataController? { itemController.fileUrlDataController }
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

extension PhotoRootModel: ItemRootControllable {
    public var configurable: any ModuleConfigurable { config }
    public var cacheControllable: (any ImageCacheControllable)? { cacheController }
    public var editControllable: any EditControllable { editController }
    public var folderListControllable: any FolderListControllable { folderListController }
    public var folderLinkControllable: any FolderListControllable { folderLinkController }
    public var viewControllable: any ViewControllable { viewController }
}

extension PhotoRootModel {
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
    public var photoGameControllable: any (GameControllable & PhotoGameControllable) {
        gameController
    }
}

// Other

public extension PhotoRootModel {
    @MainActor
    func allPhotos(with name: String) -> [UUID] {
        itemController.itemDataModel.items.filter { itemController.itemSync(for: $0)?.name == name }
    }
    
    @MainActor
    func requestImageCache(for id: UUID?) async -> Bool {
        guard let id, let item = await itemController.item(for: id), item.fileUrl != nil else { return false }
        let result = await itemController.cacheController?.photoId(for: id, item: item)
        return result != nil
    }
    
    @MainActor
    func fetchPhotoImage(for id: UUID?, useGame: Bool) async -> (AKImage, Double)? {
        guard let id else { return nil }
        let model = useGame ? gameController.gameItem(for: id) : itemController.itemOrEmpty(for: id)

        let loaderTask = Task.detached(priority: .userInitiated) {
            await self.editController.loadImage(cacheType: .image, item: model, itemId: model.id, fileUrl: model.fileUrl)
        }
        _ = await loaderTask.result

        guard let image = editController.cacheItemListModel.imageCache(cacheType: .image, itemId: model.id) else { return nil }
        return (image, model.degrees)
    }
    
    func addNewPhoto(data: Data, name: String, text: String) async -> (UUID, String) {
        let itemId = await itemController.addNew(type: .item)
        await editController.reset(name: name, itemId: itemId)
        await editController.reset(description: text, itemId: itemId)
        try? await editController.resetFile(data: data, itemId: itemId, path: "")

        let item = await itemController.item(for: itemId)
        
        return (itemId, item?.url(linkNumber: 0) ?? "")
    }

    static let thumbnailSize: CGSize = .init(width: 64.0, height: 64.0)
    
    func moveFiles() async throws {
        let itemIds = await itemController.itemDataModel.items
        for itemId in itemIds {
            let item = await itemController.itemOrEmpty(for: itemId)
            guard let fileUrl = item.fileUrl, fileUrl.location != .newCloud else { continue }
            do {
                if let newFileUrl = try await fileUrlDataController?.move(fileUrl: fileUrl, name: item.name, category: item.category.title) {
                    await editController.reset(fileUrl: newFileUrl, itemId: itemId)
                }
            } catch {
                print(error)
            }
        }
    }

    @MainActor
    func listItems() -> [PhotoModel] {
        itemController.itemDataModel.items.map {
            itemController.itemOrEmpty(for: $0)
        }
    }
    
    func itemDataCleanup() async throws {
        for itemId in await itemController.itemDataModel.items {
            guard let model = await itemController.item(for: itemId) else { continue }
            if model.displayState == 2 {
                await editController.delete(itemId: model.id)
            }
        }
    }
    
    func checkFolders(reportModel: ValidateRepairModel) async {
        let cc = ConvertController(itemController: itemController, editController: editController)
        await cc.createFilepathFoldersAndCollections(reportModel: reportModel)
    }
}
