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
    }

    let config: ModuleConfigurable
    let collectionCategory: ItemListCategory
    let dataControllable: (any DataPersistenceControllable)?
    var fileUrlDataController: FileUrlDataController?
    let itemDataModel: ItemDataModel
    let linkRegisterController: LinkRegisterController
}

extension ItemController: ItemControllable {
    typealias Model = AudioModel
}

extension ItemController: FileUrlAccessible {
    func saveFileUrl(fileUrl: FileUrl) async {
        guard let item = await item(for: fileUrl.fileId)?.copy() else { return }
        item.fileUrl = fileUrl
        await replace(model: item, isInsert: false)
    }
}

extension ItemController {
    @MainActor func hasAudio(itemId: UUID) -> Bool {
        guard let model = itemSync(for: itemId) else { return false }
        guard model.specialCategory else { return model.url != nil }
        return model.entries.contains { hasAudio(itemId: $0.childId) }
    }
    
    @MainActor func audioList(itemId: UUID) -> [AudioModel] {
        guard let model = itemSync(for: itemId) else { return [] }
        guard model.specialCategory else {
            guard model.url != nil else { return [] }
            return [model]
        }
        return model.entries.flatMap { audioList(itemId: $0.childId) }
    }
}
