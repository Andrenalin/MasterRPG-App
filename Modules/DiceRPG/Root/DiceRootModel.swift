// @copyright André Trettin

import CoreRPG
import SwiftData
import Foundation

@MainActor @Observable
public final class DiceRootModel {
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.editController = EditController()
        let itemController = ItemController(container: modelContext.container)
        self.exportController = ExportController(itemController: itemController, gameExporter: false)
        self.itemController = itemController
        self.searchModel = DiceRootModel.newSearchModel(modelContext: modelContext)
        
        self._viewController = ViewController(_root: self)
        
        itemController.cleanDeleted()
    }

    let modelContext: ModelContext
    @ObservationIgnored let editController: EditController
    @ObservationIgnored let exportController: ExportController
    @ObservationIgnored let itemController: ItemController
    @ObservationIgnored private var _viewController: ViewController? = nil
    public var viewController: ViewController {
        _viewController.unsafelyUnwrapped
    }

    let listModel = ListModel()
    let listDisplayModel = ListDisplayModel()
    let searchModel: SearchModel
    var currentSelectedItemId: UUID? {
        listModel.selected
    }
}

extension DiceRootModel {
    func newSearchModel() -> SearchModel {
        Self.newSearchModel(modelContext: modelContext)
    }
    
    static private func newSearchModel(modelContext: ModelContext) -> SearchModel {
        SearchModel(modelContext: modelContext, module: DiceDataModel.typeId, categoryTags: [.rules, .table, .value])
    }
}
