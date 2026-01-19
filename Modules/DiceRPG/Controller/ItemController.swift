// @copyright André Trettin

import CoreRPG
import Foundation
import CoreData

struct ItemController: Sendable {
    @MainActor init(config: ModuleConfiguration, dataController: DataController?, linkRegisterController: LinkRegisterController) {
        self.config = config
        
        self.dataControllable = dataController
        self.linkRegisterController = linkRegisterController

        self.itemDataModel = ItemDataModel(categoryTags: config.categoryTags)
        self.collectionCategory = config.collectionCategory
    }

    let config: ModuleConfigurable
    let collectionCategory: ItemListCategory
    let dataControllable: (any DataPersistenceControllable)?
    let itemDataModel: ItemDataModel
    let linkRegisterController: LinkRegisterController

    let diceBag = DiceModel(id: UUID(), dice: [.die4, .die6, .die8, .die10, .die12, .die20])
}

extension ItemController: ItemControllable {
    typealias Model = DiceModel
}
