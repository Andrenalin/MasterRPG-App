// @copyright André Trettin

import CoreRPG
import SwiftData
import Foundation

@MainActor @Observable
public final class DiceRootModel {
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        
        let listDisplayModel = ListDisplayModel()
        self.listDisplayModel = listDisplayModel
        let searchModel = DiceRootModel.newSearchModel(modelContext: modelContext)
        self.searchModel = searchModel

        let itemController = ItemController(container: modelContext.container)
        self.itemController = itemController
        let editController = EditController(itemControllable: itemController, fileUrlDataController: nil)
        self.editController = editController
        let listController = ListController(listModel: ListModel(), listDisplayModel: listDisplayModel, searchModel: searchModel)
        self.listController = listController
        let listLinkController = ListController(listModel: ListModel(), listDisplayModel: listDisplayModel, searchModel: searchModel)
        self.listLinkController = listLinkController

        self.exportController = ExportController(itemController: itemController, gameExporter: false)
        self._viewController = ViewController(_root: self)
        
        self._rootController = ItemRootController(module: module, listDisplayModel: listDisplayModel, searchModel: searchModel, cacheControllable: nil, editControllable: editController, itemControllable: itemController, listControllable: listController, listLinkControllable: listLinkController, viewControllable: viewControllable)

        itemController.cleanDeleted()
    }

    let modelContext: ModelContext
    public let module: NetworkModules = .dice
    
    public let listDisplayModel: ListDisplayModel
    public let searchModel: SearchModel
    
    @ObservationIgnored let editController: EditController
    @ObservationIgnored let exportController: ExportController
    @ObservationIgnored let itemController: ItemController
    @ObservationIgnored let listController: ListController
    @ObservationIgnored let listLinkController: ListController
    @ObservationIgnored private var _viewController: ViewController? = nil
    public var viewController: ViewController {
        _viewController.unsafelyUnwrapped
    }

    @ObservationIgnored private var _rootController: ItemRootController? = nil
    public var rootController: ItemRootController {
        _rootController.unsafelyUnwrapped
    }

    public var currentSelectedItemId: UUID? {
        listController.listModel.selectedItemId
    }
}

extension DiceRootModel: ItemRootControllable {
    public var cacheControllable: (any ImageCacheControllable)? { nil }
    public var editControllable: any EditControllable { editController }
    public var itemControllable: any ItemControllable { itemController }
    public var listControllable: any ListControllable { listController }
    public var listLinkControllable: any ListControllable { listLinkController }
    public var viewControllable: any ViewControllable { viewController }
}

extension DiceRootModel {
    static private func newSearchModel(modelContext: ModelContext) -> SearchModel {
        SearchModel(modelContext: modelContext, module: DiceDataModel.typeId, categoryTags: [.rules, .table, .value])
    }
}
