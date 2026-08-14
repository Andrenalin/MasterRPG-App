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
    }

    let config: ModuleConfigurable
    let collectionCategory: ItemListCategory
    var fileUrlDataController: FileUrlDataController?
    let itemDataModel: ItemDataModel
}

extension ItemController: ItemControllable {
    typealias Model = AudioModel

    @MainActor var dataControllable: (any DataPersistenceControllable)? { itemDataModel.dataController }
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
