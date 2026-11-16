// @copyright André Trettin

import CoreRPG
import Foundation
import UniformTypeIdentifiers

struct ItemController: Sendable {
    @MainActor init(config: ModuleConfiguration) {
        self.config = config

        self.itemDataModel = ItemDataModel()
        self.collectionCategory = config.collectionCategory
        
        let fileUrlDataController = FileUrlDataController(config: config)
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
    // `depth` guards against recursing forever should a folder/collection cycle ever
    // form (import, CloudKit merge conflict, …) — the same defense-in-depth every other
    // tree-walker in the codebase applies via `FolderTreeDepthLimit`. See
    // CODE_AUDIT_EditItem §5.11.
    @MainActor func hasAudio(itemId: UUID, depth: Int = 0) -> Bool {
        guard depth < FolderTreeDepthLimit.max, let model = itemSync(for: itemId) else { return false }
        guard model.specialCategory else { return model.url != nil }
        return model.entries.contains { hasAudio(itemId: $0.childId, depth: depth + 1) }
    }
}
