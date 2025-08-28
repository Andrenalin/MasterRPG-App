// @copyright André Trettin

import CoreRPG
import SwiftData
import Foundation

@MainActor @Observable
public final class PdfRootModel {
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        
        let module: NetworkModules = .pdf
        self.module = module
        
        let listDisplayModel = ListDisplayModel()
        self.listDisplayModel = listDisplayModel
        let searchModel = SearchModel(modelContext: modelContext, module: module, categoryTags: [.adventure, .character, .rules, .supplement])
        self.searchModel = searchModel
        
        let singleSelectionModel = SingleSelectionModel()
        self.singleSelectionModel = singleSelectionModel
        let multiSelectionModel = MultiSelectionModel()
        self.multiSelectionModel = multiSelectionModel

        let fileController = FileController()
        let cacheController = CacheController(fileUrlDataController: fileController.fileUrlDataController)
        let itemController = ItemController(container: modelContext.container)
        let editController = EditController(itemControllable: itemController, fileUrlDataController: fileController.fileUrlDataController)
        let listController = ListController.listController(for: .main, listDisplayModel: listDisplayModel, searchModel: searchModel)
        let listLinkController = ListController.listController(for: .link, listDisplayModel: listDisplayModel, searchModel: searchModel)
        let viewController = ViewController()
        let rootController = ItemRootController(module: module, listDisplayModel: listDisplayModel, searchModel: searchModel, singleSelectionModel: singleSelectionModel, multiSelectionModel: multiSelectionModel, cacheControllable: cacheController, editControllable: editController, itemControllable: itemController, listControllable: listController, listLinkControllable: listLinkController, viewControllable: viewController)

        self.cacheController = cacheController
        self.editController = editController
        self.exportController = ExportController(module: module, itemController: itemController, fileUrlDataController: fileController.fileUrlDataController, gameExporter: false)
        self.fileController = fileController
        self.itemController = itemController
        self.listController = listController
        self.listLinkController = listLinkController
        self.viewController = viewController
        self.rootController = rootController

        itemController.cleanDeleted()
    }
    
    let modelContext: ModelContext
    public let module: NetworkModules
    
    public let listDisplayModel: ListDisplayModel
    public let searchModel: SearchModel
    public var singleSelectionModel: SingleSelectionModel
    public var multiSelectionModel: MultiSelectionModel
    public var currentSelectedItemId: UUID? {
        listController.listModel.selectedItemId
    }

    @ObservationIgnored let cacheController: CacheController
    @ObservationIgnored let editController: EditController
    @ObservationIgnored let exportController: ExportController
    @ObservationIgnored let fileController: FileController
    @ObservationIgnored let itemController: ItemController
    @ObservationIgnored let listController: ListController
    @ObservationIgnored let listLinkController: ListController
    @ObservationIgnored public let viewController: ViewController
    @ObservationIgnored let rootController: ItemRootController
}

extension PdfRootModel: ItemRootControllable {
    public var cacheControllable: (any ImageCacheControllable)? { cacheController }
    public var editControllable: any EditControllable { editController }
    public var itemControllable: any ItemControllable { itemController }
    public var listControllable: any ListControllable { listController }
    public var listLinkControllable: any ListControllable { listLinkController }
    public var viewControllable: any ViewControllable { viewController }
}

extension PdfRootModel {
    func loadableUrl(for itemId: UUID) async -> URL? {
        guard let fileUrl = itemController.modelSync(for: itemId)?.fileUrl else { return nil }
        return await fileController.fileUrlDataController.url(for: fileUrl, action: { $0 })
    }
    
    func loadImage(for itemId: UUID, isThumbnail: Bool) async -> AKImage? {
        isThumbnail ? await cacheController.thumbnail(for: itemId) : await cacheController.photo(for: itemId)
    }
}
