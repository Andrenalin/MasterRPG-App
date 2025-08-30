// @copyright André Trettin

import CoreRPG
import DiceRPG
import SwiftData
import Foundation

@MainActor @Observable
public final class TableRootModel {
    init(modelContext: ModelContext, diceRoot: DiceRootModel) {
        self.modelContext = modelContext
        let module: NetworkModules = .table
        self.module = module
        
        let listDisplayModel = ListDisplayModel()
        self.listDisplayModel = listDisplayModel
        let searchModel = SearchModel(modelContext: modelContext, module: module, categoryTags: [.rules, .loot, .supplement])
        self.searchModel = searchModel
        let itemSelectionModel = ItemSelectionModel()
        self.itemSelectionModel = itemSelectionModel

        self.diceRoot = diceRoot

        let itemController = ItemController(container: modelContext.container)
        let editController = EditController(itemControllable: itemController, fileUrlDataController: nil)
        let listController = ListController.listController(for: .main, listDisplayModel: listDisplayModel, searchModel: searchModel)
        let listLinkController = ListController.listController(for: .link, listDisplayModel: listDisplayModel, searchModel: searchModel)

        self.editController = editController
        self.exportController = ExportController(module: module, itemController: itemController, fileUrlDataController: nil, gameExporter: false)
        self.itemController = itemController
        self.listController = listController
        self.listLinkController = listLinkController
        
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

    @ObservationIgnored let diceRoot: DiceRootModel

    //@ObservationIgnored let cacheController: CacheController
    @ObservationIgnored let editController: EditController
    @ObservationIgnored let exportController: ExportController
    @ObservationIgnored let itemController: ItemController
    @ObservationIgnored let listController: ListController
    @ObservationIgnored let listLinkController: ListController
    @ObservationIgnored public lazy var viewController: ViewController = { ViewController() }()
    @ObservationIgnored lazy var rootController: ItemRootController = {
        ItemRootController(
            module: module,
            listDisplayModel: listDisplayModel,
            searchModel: searchModel,
            itemSelectionModel: itemSelectionModel,
            cacheControllable: nil,
            editControllable: editController,
            itemControllable: itemController,
            listControllable: listController,
            listLinkControllable: listLinkController,
            viewControllable: viewController
        )
    }()
}

extension TableRootModel: ItemRootControllable {
    public var cacheControllable: (any ImageCacheControllable)? { nil }
    public var editControllable: any EditControllable { editController }
    public var itemControllable: any ItemControllable { itemController }
    public var listControllable: any ListControllable { listController }
    public var listLinkControllable: any ListControllable { listLinkController }
    public var viewControllable: any ViewControllable { viewController }
}

