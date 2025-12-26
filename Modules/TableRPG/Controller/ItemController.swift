// @copyright André Trettin

import CoreRPG
import Foundation
import Observation
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
    typealias Model = TableModel
    
    @MainActor var linkRegisterControllable: LinkRegisterControllable {
        linkRegisterController
    }

    @MainActor
    func children(for model: ItemRowModel) -> [ItemRowModel] {
        itemOrEmpty(for: model.itemId).entries.map {
            ItemRowModel(itemId: model.itemId, entryId: $0.id, typeId: config.module)
        }
    }
    
    func didDelete(model: ModelType) async {
    }
    
    func didUpdate(model: ModelType) async {
    }
    
    @MainActor
    func itemTree(from rootModel: ItemRowModel?, to childModel: ItemRowModel) -> [ItemRowModel] {
        guard let rootModel else {
            for itemId in itemDataModel.items {
                let model = ItemRowModel(itemId: itemId, typeId: config.module)
                let result = itemTree(from: model, to: childModel)
                if !result.isEmpty {
                    return result
                }
            }
            return []
        }
        
        if rootModel.itemId == childModel.itemId {
            return []
        }
        return itemTree(from: rootModel, to: childModel)
    }
}

extension ItemController {
    @MainActor
    private func itemTree(from rootModel: ItemRowModel, to childModel: ItemRowModel) -> [ItemRowModel] {
        let item = itemOrEmpty(for: rootModel.itemId)
        if item.entries.first(where: { $0.id == childModel.entryId }) != nil {
            return [childModel]
        }
        return []
    }
}
