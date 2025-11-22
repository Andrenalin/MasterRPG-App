// @copyright André Trettin

import AndrenalinKit
import Foundation
import CoreData

struct ItemController: Sendable {
    @MainActor init(dataController: DataController?, linkRegisterControllable: LinkRegisterControllable) {
        self.dataControllable = dataController
        self.linkRegisterController = linkRegisterControllable

        self.itemDataModel = ItemDataModel(categoryTags: [.rules, .table, .value], networkModule: .dice)
    }

    let collectionCategory: ItemListCategory = .diceBag
    let dataControllable: (any DataPersistenceControllable)?
    let itemDataModel: ItemDataModel
    let linkRegisterController: LinkRegisterControllable

    let diceBag = DiceModel(id: UUID(), dice: [.die4, .die6, .die8, .die10, .die12, .die20])
}

extension ItemController: ItemControllable {
    typealias Model = DiceModel
    
    @MainActor var linkRegisterControllable: LinkRegisterControllable {
        linkRegisterController
    }

    @MainActor
    func children(for model: ItemRowModel) -> [ItemRowModel] {
        [ItemRowModel(itemId: model.itemId, entryId: model.itemId, typeId: itemDataModel.networkModule)]
    }

    func didDelete(model: ModelType) async {
    }
    
    func didUpdate(model: ModelType) async {
    }
}
