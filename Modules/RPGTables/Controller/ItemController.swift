// @copyright André Trettin

import AndrenalinKit
import Foundation
import Observation
import CoreData

struct ItemController: Sendable {
    @MainActor
    init(root: TableRoot, dataController: DataController?) {
        self.root = root
        self.dataControllable = dataController
        itemDataModel = ItemDataModel(categoryTags: [.rules, .loot, .supplement, .generator], networkModule: .table)
    }

    weak var root: TableRoot!
    let collectionCategory: ItemListCategory = .bookshelf
    let dataControllable: (any DataPersistenceControllable)?
    let itemDataModel: ItemDataModel
}

extension ItemController: ItemControllable {
    typealias Model = TableModel
    
    @MainActor
    var linkRegisterControllable: LinkRegisterControllable {
        root.rootControllable.linkRegisterControllable
    }
    
    @MainActor
    func children(for model: ItemRowModel) -> [ItemRowModel] {
        itemOrEmpty(for: model.itemId).entries.map {
            ItemRowModel(itemId: model.itemId, entryId: $0.id, typeId: itemDataModel.networkModule)
        }
    }
    
    func didDelete(model: ModelType) async {
        guard let model = model as? Model else { return }
        await root.applyToAllEditController {
            await $0.didDelete(itemId: model.id)
        }
    }
    
    func didUpdate(model: ModelType) async {
        guard let model = model as? Model else { return }
        await root.applyToAllEditController {
            await $0.didUpdate(item: model)
        }
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
