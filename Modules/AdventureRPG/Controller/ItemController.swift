// @copyright André Trettin

import CoreRPG
import Foundation
import CoreData
import AudioRPG
import DiceRPG
import MapRPG
import PdfRPG
import PhotoRPG
import SpaceRPG
import CharacterRPG
import WeatherRPG
import TableRPG

struct ItemController: Sendable {
    @MainActor
    init(root: AdventureRootModel, dataController: DataController?, linkRegisterControllable: LinkRegisterControllable) {
        self.root = root
        self.dataControllable = dataController
        self.linkRegisterController = linkRegisterControllable
        
        itemDataModel = ItemDataModel(categoryTags: [.adventure, .campaign, .scenario, .rules, .supplement], networkModule: .adventure)
    }

    let root: AdventureRootModel
    let collectionCategory: ItemListCategory = .collection
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
                ItemRowModel(itemId: model.itemId, entryId: $0.id, typeId: itemDataModel.networkModule)
            }
        }
    }
    
    func didDelete(model: ModelType) async {
    }
    
    func didUpdate(model: ModelType) async {
    }
}
