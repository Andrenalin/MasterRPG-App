// @copyright André Trettin

import CoreRPG
import Foundation
import UniformTypeIdentifiers

struct ItemController: Sendable {
    @MainActor init(config: ModuleConfiguration) {
        self.config = config

        self.itemDataModel = ItemDataModel(categoryTags: config.categoryTags)
        self.collectionCategory = config.collectionCategory

        let fileUrlDataController = FileUrlDataController(moduleFolder: config.module.token, fileTypes: config.fileTypes, filenameExtension: config.filenameExtension)
        self.fileUrlDataController = fileUrlDataController
        self.cacheController = CacheController(fileUrlDataController: fileUrlDataController)
    }

    var cacheController: CacheController?
    let config: ModuleConfigurable
    let collectionCategory: ItemListCategory
    var fileUrlDataController: FileUrlDataController?
    let itemDataModel: ItemDataModel
}

extension ItemController: ItemControllable {
    typealias Model = SpaceModel

    var cacheControllable: ImageCacheControllable? { cacheController }
    @MainActor var dataControllable: (any DataPersistenceControllable)? { itemDataModel.dataController }
}
