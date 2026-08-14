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

    // `linkRegisterController` now comes from `ItemControllable`'s own
    // shared default (see CODE_AUDIT §5.5) — this module's bespoke
    // preconditionFailure message was the pattern the other 11 modules'
    // force-unwraps were fixed to match, and is now redundant with it.
}

