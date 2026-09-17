// @copyright André Trettin

import CoreRPG
import Foundation
import TableRPG

struct ItemController: Sendable {
    @MainActor init(config: ModuleConfiguration, tableRoot: TableRootModel) {
        self.config = config

        self.itemDataModel = ItemDataModel(categoryTags: config.categoryTags)
        self.collectionCategory = config.collectionCategory

        self.tableRoot = tableRoot
    }

    let config: ModuleConfigurable
    let collectionCategory: ItemListCategory
    let itemDataModel: ItemDataModel

    let tableRoot: TableRootModel
}

extension ItemController: ItemControllable {
    typealias Model = ValueModel

    @MainActor var dataControllable: (any DataPersistenceControllable)? { itemDataModel.dataController }
}

extension ItemController {
    @MainActor func subChildren(itemId: UUID, entryId: UUID?) -> [Model] {
        guard let entryId, let parent = itemSync(for: itemId) else { return [] }
        guard let valueId = parent[entryId].valueId, let value = itemSync(for: valueId) else { return [] }
        return [value]
    }
}
