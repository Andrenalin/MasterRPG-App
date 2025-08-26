// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

struct ItemController: Sendable {
    let container: ModelContainer
    let collectionCategory: ItemListCategory = .playlist
}

extension ItemController: ItemControllable {
    func encodedItemData(for id: UUID) async throws -> Data? {
        let encoder = JSONEncoder()
        let model = await itemDataCodableModel(for: id)
        return try encoder.encode(model)
    }
    
    func hasAudio(itemId: UUID) -> Bool {
        guard let model = modelSync(for: itemId) else { return false }
        guard model.specialCategory else { return model.url != nil }
        return model.entries.contains { hasAudio(itemId: $0.childId) }
    }
    
    func audioList(itemId: UUID) -> [AudioModel] {
        guard let model = modelSync(for: itemId) else { return [] }
        guard model.specialCategory else { return model.url == nil ? [] : [itemModel(model: model)] }
        return model.entries.flatMap { audioList(itemId: $0.childId) }
    }

    public func itemModel(model: ItemDataModel) -> AudioModel {
        let entries = model.entries.map { AudioEntryModel(id: $0.id, itemId: $0.childId) }
        return AudioModel(
            id: model.id,
            name: CRDT(wrappedValue: model.name),
            description: CRDT(wrappedValue: model.information),
            tags: CRDT(wrappedValue: model.tags),
            category: CRDT(wrappedValue: model.category),
            displayState: model.displayState,
            fileUrl: CRDTDataUpdate(wrappedValue: model.fileUrl),
            entries: CRDTDataUpdate(wrappedValue: entries)
        )
    }
}
