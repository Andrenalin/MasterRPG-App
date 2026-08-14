// @copyright André Trettin

import CoreRPG
import Foundation
import Observation
import CoreData

struct ItemController: Sendable {
    @MainActor init(config: ModuleConfiguration) {
        self.config = config

        self.itemDataModel = ItemDataModel(categoryTags: config.categoryTags)
        self.collectionCategory = config.collectionCategory
    }

    let config: ModuleConfigurable
    let collectionCategory: ItemListCategory
    let itemDataModel: ItemDataModel
}

extension ItemController: ItemControllable {
    typealias Model = TableModel

    @MainActor var dataControllable: (any DataPersistenceControllable)? { itemDataModel.dataController }
}
