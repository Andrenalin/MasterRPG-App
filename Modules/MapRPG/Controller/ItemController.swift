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

        self.itemDataModel = ItemDataModel(categoryTags: config.categoryTags)
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
}
