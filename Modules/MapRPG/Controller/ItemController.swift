// @copyright André Trettin

import CoreRPG
import Foundation
import PhotoRPG

struct ItemController: Sendable {
    @MainActor init(config: ModuleConfiguration, photoRoot: PhotoRootModel) {
        self.config = config

        self.itemDataModel = ItemDataModel()
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

    /// The shared delete and file-reset paths evict room images and thumbnails through this;
    /// the protocol default `nil` left map caches behind. The root keeps `cacheControllable`
    /// `nil` on purpose (maps draw their own list rows). See CODE_AUDIT_Folder §5.28.
    var cacheControllable: ImageCacheControllable? { cacheController }

    @MainActor var dataControllable: (any DataPersistenceControllable)? { itemDataModel.dataController }
}
