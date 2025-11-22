// @copyright André Trettin

import AndrenalinKit
import Foundation
import CoreData
import AudioRPG
import RPGDie
import PdfRPG
import PhotoRPG
import RPGTables
import RPGValues

struct ItemController: Sendable {
    @MainActor
    init(root: MapRootModel, dataController: DataController?) {
        self.root = root
        self.dataControllable = dataController
        itemDataModel = ItemDataModel(categoryTags: [.building, .dungeon, .map], networkModule: .map)
    }

    weak var root: MapRootModel!
    let collectionCategory: ItemListCategory = .collection
    let dataControllable: (any DataPersistenceControllable)?
    let itemDataModel: ItemDataModel
}

extension ItemController: ItemControllable {
    typealias Model = MapModel
    
    @MainActor
    var linkRegisterControllable: LinkRegisterControllable {
        root.rootControllable.linkRegisterControllable
    }
    
    @MainActor
    func children(for model: ItemRowModel) -> [ItemRowModel] {
        switch model.typeId {
        case .audio:
            return root.audioRoot.itemControllable.children(for: model)
        case .dice:
            return root.diceRoot.itemControllable.children(for: model)
        case .pdf:
            return root.pdfRoot.itemControllable.children(for: model)
        case .photo:
            return root.photoRoot.itemControllable.children(for: model)
        case .table:
            return root.tableRoot.itemControllable.children(for: model)
        case .value:
            return root.valueRoot.itemControllable.children(for: model)
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
        for entry in model.entries {
            await root.cacheController.remove(itemId: entry.id)
        }
    }
    
    func didUpdate(model: ModelType) async {
        guard let model = model as? Model else { return }
        await root.applyToAllEditController {
            await $0.didUpdate(item: model)
        }
    }
}

