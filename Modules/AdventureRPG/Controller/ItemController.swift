// @copyright André Trettin

import AudioRPG
import CharacterRPG
import CoreData
import CoreRPG
import DiceRPG
import Foundation
import MapRPG
import PdfRPG
import PhotoRPG
import SpaceRPG
import WeatherRPG
import TableRPG

struct ItemController: Sendable {
    @MainActor
    init(root: AdventureRootModel, dataController: DataController?, linkRegisterControllable: LinkRegisterControllable) {
        self.root = root
        self.config = root.config

        self.dataControllable = dataController
        self.linkRegisterController = linkRegisterControllable

        self.itemDataModel = ItemDataModel(categoryTags: config.categoryTags)
        self.collectionCategory = config.collectionCategory
    }

    let root: AdventureRootModel
    let config: ModuleConfigurable
    let collectionCategory: ItemListCategory
    let dataControllable: (any DataPersistenceControllable)?
    let itemDataModel: ItemDataModel
    let linkRegisterController: LinkRegisterControllable
}

extension ItemController: ItemControllable {
    typealias Model = AdventureModel
    
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
            return root.characterRoot.itemControllable.children(for: model)
        case .weather:
            return root.weatherRoot.itemControllable.children(for: model)
        default:
            return itemOrEmpty(for: model.itemId).entries.map {
                ItemRowModel(itemId: model.itemId, entryId: $0.id, typeId: config.module)
            }
        }
    }
    
    func didDelete(model: ModelType) async {
    }
    
    func didUpdate(model: ModelType) async {
    }
}
