// @copyright André Trettin

import CoreRPG
import Foundation
import PhotoRPG

struct ItemController: Sendable {
    @MainActor init(config: ModuleConfiguration, photoRoot: PhotoRootModel) {
        self.config = config

        self.itemDataModel = ItemDataModel(categoryTags: config.categoryTags)
        self.collectionCategory = config.collectionCategory
        
        self.cacheController = CacheController(photoRoot: photoRoot)
    }

    let config: ModuleConfigurable
    var cacheController: CacheController?
    let collectionCategory: ItemListCategory
    let itemDataModel: ItemDataModel
}

extension ItemController: ItemControllable {
    typealias Model = MapModel

    @MainActor var dataControllable: (any DataPersistenceControllable)? { itemDataModel.dataController }
}
