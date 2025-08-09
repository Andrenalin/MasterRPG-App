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
        self.searchModel = SearchModel(modelContext: modelContext, module: DiceDataModel.typeId, categoryTags: [.rules, .table, .value])
        
        itemController.cleanDeleted()
    }

    let modelContext: ModelContext
    @ObservationIgnored let editController: EditController
    @ObservationIgnored let exportController: ExportController
    @ObservationIgnored let itemController: ItemController
    
    let listModel = ListModel()
    let searchModel: SearchModel
    var currentSelectedItemId: UUID?
}
