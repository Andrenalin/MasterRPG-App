// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

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
    typealias Model = GeneratorModel

    @MainActor var dataControllable: (any DataPersistenceControllable)? { itemDataModel.dataController }
    @MainActor var linkRegisterController: LinkRegisterController { itemDataModel.linkRegisterController! }
}
