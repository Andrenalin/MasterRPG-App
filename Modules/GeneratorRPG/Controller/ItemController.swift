// @copyright André Trettin

import AndrenalinKit
import Foundation
import SwiftData

struct ItemController: Sendable {
    @MainActor init(dataController: DataController?, linkRegisterControllable: LinkRegisterControllable) {
        self.dataControllable = dataController
        self.linkRegisterController = linkRegisterControllable

        self.itemDataModel = ItemDataModel(categoryTags: [.rules, .table, .value], networkModule: .generator)
    }

    let collectionCategory: ItemListCategory = .diceBag
    let dataControllable: (any DataPersistenceControllable)?
    let itemDataModel: ItemDataModel
    let linkRegisterController: LinkRegisterControllable
}

extension ItemController: ItemControllable {
    typealias Model = GeneratorModel
    
    @MainActor var linkRegisterControllable: LinkRegisterControllable {
        linkRegisterController
    }

    @MainActor
    func children(for model: ItemRowModel) -> [ItemRowModel] {
        [ItemRowModel(itemId: model.itemId, entryId: model.itemId, typeId: itemDataModel.networkModule)]
    }

    func didDelete(model: ModelType) async {}
    
    func didUpdate(model: ModelType) async {}
}
