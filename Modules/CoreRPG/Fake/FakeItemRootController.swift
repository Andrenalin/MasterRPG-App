// @copyright André Trettin

import Foundation
import SwiftData

@Observable
final class FakeItemRootController: ItemRootControllable {
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        
        let listModel = ListModel()
        self.listModel = listModel
        let listDisplayModel = ListDisplayModel()
        self.listDisplayModel = listDisplayModel
        let searchModel = SearchModel(modelContext: modelContext, module: .audio, categoryTags: [.music, .sound])
        self.searchModel = searchModel

        let itemController = FakeItemController(container: modelContext.container)
        self.editControllable = FakeEditController(itemControllable: itemController, fileUrlDataController: nil)
        self.itemControllable = itemController
        self.listControllable = FakeListController(listModel: listModel, listDisplayModel: listDisplayModel, searchModel: searchModel)
    }

    let modelContext: ModelContext
    
    let module: NetworkModules = .audio
    let listModel: ListModel
    let listDisplayModel: ListDisplayModel
    let searchModel: SearchModel
    
    let editControllable: any EditControllable
    let itemControllable: any ItemControllable
    let listControllable: any ListControllable
}
