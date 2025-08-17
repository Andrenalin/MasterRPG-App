// @copyright André Trettin

import CoreRPG
import SwiftData
import Foundation

@MainActor @Observable
public final class DiceRootModel {
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        
        let listModel = ListModel()
        self.listModel = listModel
        let listDisplayModel = ListDisplayModel()
        self.listDisplayModel = listDisplayModel
        let searchModel = DiceRootModel.newSearchModel(modelContext: modelContext)
        self.searchModel = searchModel

        self.editController = EditController()
        let itemController = ItemController(container: modelContext.container)
        self.exportController = ExportController(itemController: itemController, gameExporter: false)
        self.itemController = itemController
        self.listController = ListController.listController(for: .main, listModel: listModel, listDisplayModel: listDisplayModel, searchModel: searchModel)
        self.listLinkController = ListController.listController(for: .link, listModel: listModel, listDisplayModel: listDisplayModel, searchModel: searchModel)
        self._viewController = ViewController(_root: self)
        
        itemController.cleanDeleted()
    }

    let modelContext: ModelContext
    
    let listModel: ListModel
    let listDisplayModel: ListDisplayModel
    let searchModel: SearchModel
    
    @ObservationIgnored let editController: EditController
    @ObservationIgnored let exportController: ExportController
    @ObservationIgnored let itemController: ItemController
    @ObservationIgnored let listController: ListController
    @ObservationIgnored let listLinkController: ListController
    @ObservationIgnored private var _viewController: ViewController? = nil
    public var viewController: ViewController {
        _viewController.unsafelyUnwrapped
    }

    var currentSelectedItemId: UUID? {
        listModel.selected
    }
}

extension DiceRootModel {
    static private func newSearchModel(modelContext: ModelContext) -> SearchModel {
        SearchModel(modelContext: modelContext, module: DiceDataModel.typeId, categoryTags: [.rules, .table, .value])
    }
}
