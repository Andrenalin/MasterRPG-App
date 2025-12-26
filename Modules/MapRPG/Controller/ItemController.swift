// @copyright André Trettin

import CoreRPG
import Foundation
import CoreData
import AudioRPG
import DiceRPG
import PdfRPG
import PhotoRPG
import TableRPG
import CharacterRPG

struct ItemController: Sendable {
    @MainActor
    init(root: MapRootModel, dataController: DataController?, linkRegisterControllable: LinkRegisterControllable) {
        self.root = root
        self.config = root.config

        self.dataControllable = dataController
        self.linkRegisterController = linkRegisterControllable

        self.itemDataModel = ItemDataModel(categoryTags: config.categoryTags, networkModule: config.module)
        self.collectionCategory = config.collectionCategory
        self.cacheController = CacheController(photoRoot: root.photoRoot)
    }

    let root: MapRootModel
    let config: ModuleConfigurable
    var cacheController: CacheController?
    let collectionCategory: ItemListCategory
    let dataControllable: (any DataPersistenceControllable)?
    let itemDataModel: ItemDataModel
    let linkRegisterController: LinkRegisterControllable
}

extension ItemController: ItemControllable {
    typealias Model = MapModel
    
    @MainActor
    var linkRegisterControllable: LinkRegisterControllable {
        linkRegisterController
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
            return root.characterRoot.itemControllable.children(for: model)
        default:
            return itemOrEmpty(for: model.itemId).entries.map {
                ItemRowModel(itemId: model.itemId, entryId: $0.id, typeId: config.module)
            }
        }
    }
    
    func didDelete(model: ModelType) async {
        guard let model = model as? Model else { return }
        for entry in model.entries {
            await cacheController?.remove(itemId: entry.id)
        }
    }
    
    func didUpdate(model: ModelType) async {
    }
}

