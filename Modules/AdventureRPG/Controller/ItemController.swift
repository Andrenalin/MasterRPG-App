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
    init(config: ModuleConfiguration, dataController: DataController?, linkRegisterControllable: LinkRegisterControllable) {
        self.config = config

        self.dataControllable = dataController
        self.linkRegisterController = linkRegisterControllable

        self.itemDataModel = ItemDataModel(categoryTags: config.categoryTags)
        self.collectionCategory = config.collectionCategory
    }

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
}
