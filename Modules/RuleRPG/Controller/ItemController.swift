// @copyright André Trettin

import CoreRPG
import Foundation

struct ItemController: Sendable {
    @MainActor
    init(config: ModuleConfiguration) {
        self.config = config
        itemDataModel = ItemDataModel(categoryTags: config.categoryTags)
        collectionCategory = config.collectionCategory
    }

    let config: ModuleConfigurable
    let collectionCategory: ItemListCategory
    let itemDataModel: ItemDataModel
}

extension ItemController: ItemControllable {
    typealias Model = RuleModel

    @MainActor
    var dataControllable: (any DataPersistenceControllable)? {
        itemDataModel.dataController
    }

    @MainActor
    var linkRegisterController: LinkRegisterController {
        guard let controller = itemDataModel.linkRegisterController else {
            preconditionFailure("RuleRPG requires a LinkRegisterController after setup.")
        }
        return controller
    }
}

