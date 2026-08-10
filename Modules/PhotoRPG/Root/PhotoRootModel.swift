// @copyright André Trettin

import CoreRPG
import CoreData
import SwiftData
import SwiftUI

@MainActor @Observable
public final class PhotoRootModel {
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

#if os(visionOS)
        self.imagePresentationModel = ImagePresentationModel()
#endif

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
        let editController = EditController(itemController: itemController, linkController: linkController, sheetController: sheetController, tagController: tagController)
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
        self.openFileWindowModel = OpenFileWindowModel(windowId: NetworkModules.photo.viewerWindowId, route: { DetailRoute.viewer($0) })

        self.rootController = ItemRootController(
            rootManager: nil,
            config: config,
            navigationModel: navigationModel,
            inspectorEditorLinkModel: editorLinkModel,
            openFileWindowModel: openFileWindowModel,
            itemSelectionModel: itemSelectionModel,
            removeEntryListModel: removeEntryListModel,
            cacheControllable: itemController.cacheController,
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

    @MainActor public func setUp(context: NSManagedObjectContext?, batchContext: NSManagedObjectContext?, rootManager: RootManager, adventureRootControllable: any RootExportControllable, linkRegisterController: LinkRegisterController) {
        rootController.rootManager = rootManager

        itemController.itemDataModel.dataController = context.map { DataController(context: $0, batchContext: batchContext, token: config.module.token) }
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

    #if os(visionOS)
    public let imagePresentationModel: ImagePresentationModel
    #endif

    let searchModel: SearchModel
    let listDisplayModel: ListDisplayModel

    var cacheController: CacheController? { itemController.cacheController }
    public var fileUrlDataController: FileUrlDataController? { itemController.fileUrlDataController }

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
extension PhotoRootModel: ItemRootControllable {
    @MainActor public var currentSelectedItemId: UUID? { folderListController.listModel.selectedItemId }

    public var rootManager: RootManager? { rootController.rootManager }
    public var configurable: any ModuleConfigurable { config }
    public var cacheControllable: (any ImageCacheControllable)? { cacheController }
    public var editControllable: any EditControllable { editController }
    public var folderListControllable: any FolderListControllable { folderListController }
    public var folderLinkControllable: any FolderListControllable { folderLinkController }
    public var inspectorEditorLinkModel: EditorLinkModel? { editorLinkModel }
    public var sheetControllable: any SheetControllable { sheetController }
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
    public var searchControllable: any SearchControllable { searchController }
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

    /// Lightweight source for callers that only need a small preview (e.g. a Map
    /// room-crop thumbnail) — decodes a downsampled image via ImageIO instead of the
    /// full-resolution decode that `fetchPhotoImage`/`requestImageCache` perform, and
    /// reports the scale to map rects defined in the original image's pixel space.
    @MainActor
    func fetchPhotoThumbnailSource(for id: UUID?, maxPixelSize: CGFloat) async -> (image: AKImage, scale: CGFloat, degrees: Double)? {
        guard let id, let item = await itemController.item(for: id), let fileUrl = item.fileUrl,
              let fileUrlDataController else { return nil }
        if !fileUrl.hasUnconvertedData, await !fileUrlDataController.isAvailableWithoutDownloading(fileUrl) {
            return nil
        }
        let result: AKImage.DownsampledResult?
        if let data = fileUrl.data {
            result = AKImage.downsampledThumbnailWithScale(from: data, maxPixelSize: maxPixelSize)
        } else if let data = try? await fileUrlDataController.loadData(for: fileUrl) {
            result = AKImage.downsampledThumbnailWithScale(from: data, maxPixelSize: maxPixelSize)
        } else {
            result = await fileUrlDataController.url(for: fileUrl) { url -> AKImage.DownsampledResult? in
                guard let url else { return nil }
                return AKImage.downsampledThumbnailWithScale(from: url, maxPixelSize: maxPixelSize)
            }
        }
        guard let result else { return nil }
        return (result.image, result.scale, item.degrees)
    }

    @MainActor
    func fetchPhotoImage(for id: UUID?, useGame: Bool) async -> (AKImage, Double)? {
        guard let id else { return nil }
        let model = useGame ? gameController.gameItem(for: id) : itemController.itemOrEmpty(for: id)

        let loaderTask = Task(priority: .userInitiated) {
            await self.editController.loadImage(cacheType: .image, item: model, itemId: model.id, fileUrl: model.fileUrl)
        }
        _ = await loaderTask.result

        guard let image = editController.cacheController?.cachedImage(for: model.id) else { return nil }
        return (image, model.degrees)
    }

    static let thumbnailSize: CGSize = .init(width: 64.0, height: 64.0)

    @MainActor
    func listItems() -> [PhotoModel] {
        itemController.itemDataModel.items.map {
            itemController.itemOrEmpty(for: $0)
        }
    }

    func itemDataCleanup() async throws {
        for itemId in itemController.itemDataModel.items {
            guard let model = await itemController.item(for: itemId) else { continue }
            if model.displayState == 2 {
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
