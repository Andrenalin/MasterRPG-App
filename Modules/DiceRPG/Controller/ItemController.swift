// @copyright André Trettin

import CoreRPG
import Foundation
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

    let diceBag = DiceModel(id: UUID(), dice: [.die4, .die6, .die8, .die10, .die12, .die20])
}

extension ItemController: ItemControllable {
    typealias Model = DiceModel

    @MainActor var dataControllable: (any DataPersistenceControllable)? { itemDataModel.dataController }
}
