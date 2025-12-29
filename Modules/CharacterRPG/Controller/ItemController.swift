// @copyright André Trettin

import CoreRPG
import Foundation
import TableRPG

struct ItemController: Sendable {
    @MainActor init(config: ModuleConfiguration, tableRoot: TableRootModel, dataController: DataController?, linkRegisterControllable: LinkRegisterControllable) {
        self.config = config
        
        self.dataControllable = dataController
        self.linkRegisterController = linkRegisterControllable
        
        self.itemDataModel = ItemDataModel(categoryTags: config.categoryTags)
        self.collectionCategory = config.collectionCategory

        self.tableRoot = tableRoot
    }

    let config: ModuleConfigurable
    let collectionCategory: ItemListCategory
    let dataControllable: (any DataPersistenceControllable)?
    let itemDataModel: ItemDataModel
    let linkRegisterController: LinkRegisterControllable

    let tableRoot: TableRootModel
}

extension ItemController: ItemControllable {
    typealias Model = ValueModel
    
    @MainActor var linkRegisterControllable: LinkRegisterControllable {
        linkRegisterController
    }

    func didDelete(model: ModelType) async {
        guard let model = model as? ValueModel else { return }
//        for entry in model.entries {
//            await root.editController.remove(entryId: entry.id, from: model, isDeepRemove: true)
//        }
    }
    
    func didUpdate(model: ModelType) async {
    }
}
