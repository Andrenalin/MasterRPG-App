// @copyright André Trettin

import CoreRPG
import Foundation
import PhotoRPG

struct ItemController: Sendable {
    @MainActor init(config: ModuleConfiguration, photoRoot: PhotoRootModel, dataController: DataController?, linkRegisterControllable: LinkRegisterControllable) {
        self.config = config

        self.dataControllable = dataController
        self.linkRegisterController = linkRegisterControllable

        self.itemDataModel = ItemDataModel(categoryTags: config.categoryTags)
        self.collectionCategory = config.collectionCategory
        
        self.cacheController = CacheController(photoRoot: photoRoot)
    }

    let config: ModuleConfigurable
    var cacheController: CacheController?
    let collectionCategory: ItemListCategory
    let dataControllable: (any DataPersistenceControllable)?
    let itemDataModel: ItemDataModel
    let linkRegisterController: LinkRegisterControllable
}

extension ItemController: ItemControllable {
    typealias Model = MapModel
    
    @MainActor var linkRegisterControllable: LinkRegisterControllable { linkRegisterController }
}
