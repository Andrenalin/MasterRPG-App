// @copyright André Trettin

import AndrenalinKit
import Foundation
import CoreData
import RPGAudios
import RPGDie
import RPGMaps
import RPGPdfs
import PhotoRPG
import SpaceRPG
import RPGValues
import RPGWeathers
import RPGTables

struct ItemController: Sendable {
    @MainActor
    init(root: AdventureRootModel, dataController: DataController?) {
        self.root = root
        self.dataControllable = dataController
        itemDataModel = ItemDataModel(categoryTags: [.adventure, .campaign, .scenario, .rules, .supplement], networkModule: .adventure)
    }

    weak var root: AdventureRootModel!
    let collectionCategory: ItemListCategory = .collection
    let dataControllable: (any DataPersistenceControllable)?
    let itemDataModel: ItemDataModel
}

extension ItemController: ItemControllable {
    typealias Model = AdventureModel
    
    @MainActor
    var linkRegisterControllable: LinkRegisterControllable {
        root.linkRegisterController
    }
    
    @MainActor
    func children(for model: ItemRowModel) -> [ItemRowModel] {
        switch model.typeId {
        case .audio:
            return root.audioRoot.itemControllable.children(for: model)
        case .dice:
            return root.diceRoot.itemControllable.children(for: model)
        case .map:
            return root.mapRoot.itemControllable.children(for: model)
        case .pdf:
            return root.pdfRoot.itemControllable.children(for: model)
        case .photo:
            return root.photoRoot.itemControllable.children(for: model)
        case .space:
            return root.spaceRoot.itemControllable.children(for: model)
        case .table:
            return root.tableRoot.itemControllable.children(for: model)
        case .value:
            return root.valueRoot.itemControllable.children(for: model)
        case .weather:
            return root.weatherRoot.itemControllable.children(for: model)
        default:
            return itemOrEmpty(for: model.itemId).entries.map {
                ItemRowModel(itemId: model.itemId, entryId: $0.id, typeId: itemDataModel.networkModule)
            }
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
}
