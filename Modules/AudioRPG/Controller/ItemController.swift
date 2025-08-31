// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

struct ItemController: Sendable {
    let container: ModelContainer
    let collectionCategory: ItemListCategory = .playlist
}

extension ItemController: ItemControllable {
    @MainActor func encodedItemData(for id: UUID) throws -> Data? {
        let encoder = JSONEncoder()
        let model = itemDataCodableModel(for: id)
        return try encoder.encode(model)
    }
    
    @MainActor func fileUrl(id: UUID, url: URL?) -> FileUrl? {
        guard let url else { return nil }
        return FileUrl(fileId: id, url: url, location: .cloud, module: NetworkModules.audio.token)
    }
    
    func hasAudio(itemId: UUID) -> Bool {
        guard let model = modelSync(for: itemId) else { return false }
        guard model.specialCategory else { return model.url != nil }
        return model.entries.contains { hasAudio(itemId: $0.childId) }
    }
    
    @MainActor func audioList(itemId: UUID) -> [ItemDataCodableModel] {
        guard let model = modelSync(for: itemId) else { return [] }
        guard model.specialCategory else {
            guard model.url != nil, let item = itemModel(model: model) else { return [] }
            return [item]
        }
        return model.entries.flatMap { audioList(itemId: $0.childId) }
    }

    @MainActor func itemModel(model: ItemDataModel) -> ItemDataCodableModel? {
        itemDataCodableModel(for: model.id)
    }
}
