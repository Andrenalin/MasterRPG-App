// @copyright André Trettin

import AndrenalinKit
import Foundation
import CoreData

struct ItemController: Sendable {
    @MainActor
    init(root: WeatherRoot, dataController: DataController?) {
        self.root = root
        self.dataControllable = dataController
        itemDataModel = ItemDataModel(categoryTags: [.adventure, .map, .scenario], networkModule: .weather)
    }

    weak var root: WeatherRoot!
    let collectionCategory: ItemListCategory = .collection
    let dataControllable: (any DataPersistenceControllable)?
    let itemDataModel: ItemDataModel
}

extension ItemController: ItemControllable {
    typealias Model = WeatherModel
    
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
