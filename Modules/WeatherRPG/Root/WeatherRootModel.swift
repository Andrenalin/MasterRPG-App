// @copyright André Trettin

import CoreRPG
import SwiftData
import Foundation

@MainActor @Observable
public final class WeatherRootModel {
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        
        let module: NetworkModules = .photo
        self.module = module
        
        let listDisplayModel = ListDisplayModel()
        self.listDisplayModel = listDisplayModel
        let searchModel = SearchModel(modelContext: modelContext, module: module, categoryTags: [.building, .item, .supplement])
        self.searchModel = searchModel
        
        let itemController = ItemController(container: modelContext.container)
        let editController = EditController(itemControllable: itemController, fileUrlDataController: nil)
        let listController = ListController.listController(for: .main, listDisplayModel: listDisplayModel, searchModel: searchModel)
        let listLinkController = ListController.listController(for: .link, listDisplayModel: listDisplayModel, searchModel: searchModel)
        let viewController = ViewController()
        
        //self.cacheController = CacheController(fileUrlDataController: nil)
        self.editController = editController
        self.exportController = ExportController(module: module, itemController: itemController, fileUrlDataController: nil, gameExporter: false)
        self.itemController = itemController
        self.listController = listController
        self.listLinkController = listLinkController
        self.viewController = viewController
        self.rootController = ItemRootController(module: module, listDisplayModel: listDisplayModel, searchModel: searchModel, cacheControllable: nil, editControllable: editController, itemControllable: itemController, listControllable: listController, listLinkControllable: listLinkController, viewControllable: viewController)
        
        itemController.cleanDeleted()
    }
    
    let modelContext: ModelContext
    public let module: NetworkModules
    
    public let listDisplayModel: ListDisplayModel
    public let searchModel: SearchModel
    
    //@ObservationIgnored let cacheController: CacheController
    @ObservationIgnored let editController: EditController
    @ObservationIgnored let exportController: ExportController
    @ObservationIgnored let itemController: ItemController
    @ObservationIgnored let listController: ListController
    @ObservationIgnored let listLinkController: ListController
    @ObservationIgnored public let viewController: ViewController
    @ObservationIgnored let rootController: ItemRootController
    
    public var currentSelectedItemId: UUID? {
        listController.listModel.selectedItemId
    }
}

extension WeatherRootModel: ItemRootControllable {
    public var cacheControllable: (any ImageCacheControllable)? { nil }
    public var editControllable: any EditControllable { editController }
    public var itemControllable: any ItemControllable { itemController }
    public var listControllable: any ListControllable { listController }
    public var listLinkControllable: any ListControllable { listLinkController }
    public var viewControllable: any ViewControllable { viewController }
}

