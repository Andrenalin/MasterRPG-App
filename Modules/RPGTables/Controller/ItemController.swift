// @copyright André Trettin

import AndrenalinKit
import Foundation
import Observation
import CoreData

struct ItemController: Sendable {
    @MainActor init(dataController: DataController?, linkRegisterControllable: LinkRegisterControllable) {
        self.dataControllable = dataController
        self.linkRegisterController = linkRegisterControllable

        self.itemDataModel = ItemDataModel(categoryTags: [.rules, .loot, .supplement, .generator], networkModule: .table)
    }

    let collectionCategory: ItemListCategory = .bookshelf
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
            ItemRowModel(itemId: model.itemId, entryId: $0.id, typeId: itemDataModel.networkModule)
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
                let model = ItemRowModel(itemId: itemId, typeId: itemDataModel.networkModule)
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
