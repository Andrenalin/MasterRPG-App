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
        
        let itemSelectionModel = ItemSelectionModel()
        self.itemSelectionModel = itemSelectionModel

        itemController.cleanDeleted()
    }
    
    let modelContext: ModelContext
    public let module: NetworkModules
    
    public let listDisplayModel: ListDisplayModel
    public let searchModel: SearchModel
    public var itemSelectionModel: ItemSelectionModel
    public var currentSelectedItemId: UUID? {
        listController.listModel.selectedItemId
    }
    public let removeEntryListModel = RemoveEntryListModel()
    
    @ObservationIgnored lazy var cacheController: CacheController = {
        CacheController(fileUrlDataController: fileController.fileUrlDataController)
    }()
    @ObservationIgnored lazy var editController: EditController = {
        EditController(itemController: itemController, fileUrlDataController: fileController.fileUrlDataController)
    }()
    @ObservationIgnored lazy var exportController: ExportController = {
        ExportController(module: module, itemController: itemController, fileUrlDataController: fileController.fileUrlDataController, gameExporter: false)
    }()
    @ObservationIgnored lazy var fileController: FileController = {
        FileController()
    }()
    @ObservationIgnored lazy var importController: ImportController = {
        ImportController(itemController: itemController, fileUrlDataController: fileController.fileUrlDataController, module: module)
    }()
    @ObservationIgnored lazy var itemController: ItemController = {
        ItemController(container: modelContext.container)
    }()
    @ObservationIgnored lazy var linkController: LinkController = {
        LinkController(module: module, itemController: itemController)
    }()
    @ObservationIgnored lazy var listController: ListController = {
        ListController.listController(for: .main, listDisplayModel: listDisplayModel, searchModel: searchModel)
    }()
    @ObservationIgnored lazy var listLinkController: ListController = {
        ListController.listController(for: .link, listDisplayModel: listDisplayModel, searchModel: searchModel)
    }()
    @ObservationIgnored public lazy var viewController: ViewController = {
        ViewController()
    }()
    @ObservationIgnored lazy var rootController: ItemRootController = {
        ItemRootController(
            module: module,
            listDisplayModel: listDisplayModel,
            searchModel: searchModel,
            itemSelectionModel: itemSelectionModel,
            removeEntryListModel: removeEntryListModel,
            cacheControllable: cacheController,
            editControllable: editController,
            exportControllable: exportControllable,
            itemControllable: itemController,
            linkControllable: linkController,
            listControllable: listController,
            listLinkControllable: listLinkController,
            viewControllable: viewController
        )
    }()
}

extension PdfRootModel: ItemRootControllable {
    public var cacheControllable: (any ImageCacheControllable)? { cacheController }
    public var editControllable: any EditControllable { editController }
    public var exportControllable: any ExportControllable { exportController }
    public var importControllable: any ImportControllable { importController }
    public var itemControllable: any ItemControllable { itemController }
    public var linkControllable: any LinkControllable { linkController }
    public var listControllable: any ListControllable { listController }
    public var listLinkControllable: any ListControllable { listLinkController }
    public var viewControllable: any ViewControllable { viewController }
}

extension PdfRootModel {
    func loadableUrl(for itemId: UUID) async -> URL? {
        guard let fileUrl = itemController.item(for: itemId)?.fileUrl else { return nil }
        return await fileController.fileUrlDataController.url(for: fileUrl, action: { $0 })
    }
    
    func loadImage(for itemId: UUID, isThumbnail: Bool) async -> AKImage? {
        isThumbnail ? await cacheController.thumbnail(for: itemId) : await cacheController.photo(for: itemId)
    }
}
