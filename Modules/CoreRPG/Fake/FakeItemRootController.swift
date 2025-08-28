// @copyright André Trettin

import Foundation
import SwiftData

@Observable
public final class FakeItemRootController: ItemRootControllable {
    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
        
        let module = NetworkModules.audio
        self.module = module
        
        let listDisplayModel = ListDisplayModel()
        self.listDisplayModel = listDisplayModel
        let searchModel = SearchModel(modelContext: modelContext, module: .audio, categoryTags: [.music, .sound])
        self.searchModel = searchModel

        let singleSelectionModel = SingleSelectionModel()
        self.singleSelectionModel = singleSelectionModel
        let multiSelectionModel = MultiSelectionModel()
        self.multiSelectionModel = multiSelectionModel

        self.cacheControllable = nil
        let itemController = FakeItemController(container: modelContext.container)
        self.itemControllable = itemController
        let editController = FakeEditController(itemControllable: itemController, fileUrlDataController: nil)
        self.editControllable = editController
        let listController = FakeListController(listModel: ListModel(), listDisplayModel: listDisplayModel, searchModel: searchModel)
        self.listControllable = listController
        let listLinkController = FakeListController(listModel: ListModel(), listDisplayModel: listDisplayModel.newListDisplayModel, searchModel: searchModel.newSearchModel)
        self.listLinkControllable = listController
        self.viewControllable = FakeViewController(goupViewType: .item, thumbnailRowViewType: .none)
        
        let rootController =
        ItemRootController(module: module, listDisplayModel: listDisplayModel, searchModel: searchModel, singleSelectionModel: singleSelectionModel, multiSelectionModel: multiSelectionModel, cacheControllable: nil, editControllable: editController, itemControllable: itemController, listControllable: listController, listLinkControllable: listLinkController, viewControllable: viewControllable)
        self.rootController = rootController
    }

    let modelContext: ModelContext
    public let module: NetworkModules
    
    public let listDisplayModel: ListDisplayModel
    public let searchModel: SearchModel
    
    public var singleSelectionModel: SingleSelectionModel
    public var multiSelectionModel: MultiSelectionModel
    public var currentSelectedItemId: UUID? = nil

    public let cacheControllable: (any ImageCacheControllable)?
    public let editControllable: any EditControllable
    public let itemControllable: any ItemControllable
    public let listControllable: any ListControllable
    public let listLinkControllable: any ListControllable
    public let viewControllable: any ViewControllable
    
    public var rootController: ItemRootController
}
