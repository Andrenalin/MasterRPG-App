// @copyright André Trettin

import Foundation
import SwiftData

@Observable
public final class FakeItemRootController: ItemRootControllable {
    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
        
        let module = NetworkModules.audio
        self.module = module
        let listModel = ListModel()
        self.listModel = listModel
        let listDisplayModel = ListDisplayModel()
        self.listDisplayModel = listDisplayModel
        let searchModel = SearchModel(modelContext: modelContext, module: .audio, categoryTags: [.music, .sound])
        self.searchModel = searchModel

        let itemController = FakeItemController(container: modelContext.container)
        self.itemControllable = itemController
        let editController = FakeEditController(itemControllable: itemController, fileUrlDataController: nil)
        self.editControllable = editController
        let listController = FakeListController(listModel: listModel, listDisplayModel: listDisplayModel, searchModel: searchModel)
        self.listControllable = listController
        let listLinkController = FakeListController(listModel: listModel, listDisplayModel: listDisplayModel, searchModel: searchModel)
        self.listLinkControllable = listController

        let rootController =
        ItemRootController(module: module, listDisplayModel: listDisplayModel, searchModel: searchModel, editControllable: editController, itemControllable: itemController, listControllable: listController, listLinkControllable: listLinkController)
        self.rootController = rootController
    }

    let modelContext: ModelContext
    
    public let module: NetworkModules
    public let listModel: ListModel
    public let listDisplayModel: ListDisplayModel
    public let searchModel: SearchModel
    
    public var currentSelectedItemId: UUID? = nil
    
    public let editControllable: any EditControllable
    public let itemControllable: any ItemControllable
    public let listControllable: any ListControllable
    public let listLinkControllable: any ListControllable
    
    public var rootController: ItemRootController
}
