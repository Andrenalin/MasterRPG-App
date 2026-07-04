// @copyright André Trettin

import CoreRPG
import Foundation
import UniformTypeIdentifiers

struct ItemController: Sendable {
    @MainActor init(config: ModuleConfiguration, dataController: DataController?, linkRegisterController: LinkRegisterController) {
        self.config = config
        
        self.dataControllable = dataController
        self.linkRegisterController = linkRegisterController

        self.itemDataModel = ItemDataModel(categoryTags: config.categoryTags)
        self.collectionCategory = config.collectionCategory

        let fileUrlDataController = FileUrlDataController(moduleFolder: config.module.token, fileTypes: config.fileTypes, filenameExtension: config.filenameExtension, fileUrlAccess: self)
        self.fileUrlDataController = fileUrlDataController
        self.cacheController = CacheController(fileUrlDataController: fileUrlDataController)
    }

    var cacheController: CacheController?
    let config: ModuleConfigurable
    let collectionCategory: ItemListCategory
    let dataControllable: (any DataPersistenceControllable)?
    var fileUrlDataController: FileUrlDataController?
    let itemDataModel: ItemDataModel
    let linkRegisterController: LinkRegisterController
}

extension ItemController: ItemControllable {
    typealias Model = SpaceModel

    var cacheControllable: ImageCacheControllable? { cacheController }
}

extension ItemController: FileUrlAccessible {
    // Isolated witness for the async requirement — callers already await.
    @MainActor func saveFileUrl(fileUrl: FileUrl) async {
        guard let item = await item(for: fileUrl.fileId)?.copy() else { return }
        if let fileId = item.fileUrl?.fileId {
            await cacheController?.remove(itemId: fileId)
        }
        item.fileUrl = fileUrl
        replace(model: item, isInsert: false)
    }
}
