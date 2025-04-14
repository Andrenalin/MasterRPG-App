// @copyright André Trettin

import AndrenalinKit
import Foundation
import CoreData

struct ItemController: Sendable {
    @MainActor
    init(root: DiceRoot, dataController: DataController?) {
        self.root = root
        self.dataControllable = dataController
        itemDataModel = ItemDataModel(categoryTags: [.rules, .table, .value], networkModule: .dice)
    }

    weak var root: DiceRoot!
    let dataControllable: (any DataPersistenceControllable)?
    let itemDataModel: ItemDataModel
    
    let diceBag = DiceModel(id: UUID(), dice: [.die4, .die6, .die8, .die10, .die12, .die20])
}

extension ItemController: ItemControllable {
    typealias Model = DiceModel
    
    @MainActor
    var linkRegisterControllable: LinkRegisterControllable {
        root.rootControllable.linkRegisterControllable
    }

    @MainActor
    func children(for model: ItemRowModel) -> [ItemRowModel] {
        [ItemRowModel(itemId: model.itemId, entryId: model.itemId, typeId: itemDataModel.networkModule)]
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
}
