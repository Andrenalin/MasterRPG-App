// @copyright André Trettin

import CoreRPG
import Foundation
import CoreData

struct ItemController: Sendable {
    @MainActor init(config: ModuleConfiguration, dataController: DataController?, linkRegisterControllable: LinkRegisterControllable) {
        self.config = config
        self.dataControllable = dataController
        self.linkRegisterController = linkRegisterControllable

        self.itemDataModel = ItemDataModel(categoryTags: config.categoryTags)
        
        self.collectionCategory = config.collectionCategory
    }

    let config: ModuleConfigurable
    let collectionCategory: ItemListCategory
    let dataControllable: (any DataPersistenceControllable)?
    let itemDataModel: ItemDataModel
    let linkRegisterController: LinkRegisterControllable
}

extension ItemController: ItemControllable {
    typealias Model = WeatherModel
    
    @MainActor var linkRegisterControllable: LinkRegisterControllable {
        linkRegisterController
    }

    @MainActor
    func children(for model: ItemRowModel) -> [ItemRowModel] {
        [ItemRowModel(itemId: model.itemId, entryId: model.itemId, typeId: config.module)]
    }

    func didDelete(model: ModelType) async {
    }
    
    func didUpdate(model: ModelType) async {
    }
}
