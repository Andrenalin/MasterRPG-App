// @copyright André Trettin

import CoreRPG
import Foundation

/// Sendable value snapshot of a ValueModel — the only representation that crosses
/// the Core Data context boundary. Not Codable: the .gmz wire format stays on
/// ValueModel's Codable implementation.
struct ValueSnapshot: Sendable, Identifiable {
    let id: UUID
    let name: CRDT<String>
    let description: CRDT<String>
    let tags: CRDT<[String]>
    let category: CRDT<ItemListCategory>
    let displayState: Int
    let photoId: CRDT<UUID?>
    let photos: CRDTDataUpdate<[UUID]>
    let entries: CRDTDataUpdate<[ValueEntryModel]>
    let parentId: UUID?
    let diceId: UUID?
    let groupId: UUID?
}

extension ValueSnapshot {
    @MainActor
    init(_ model: ValueModel) {
        id = model.id
        name = model.name_
        description = model.description_
        tags = model.tags_
        category = model.category_
        displayState = model.displayState
        photoId = model.photoId_
        photos = model.photos_
        entries = model.entries_
        parentId = model.parentId
        diceId = model.diceId
        groupId = model.groupId
    }

    @MainActor
    func makeModel() -> ValueModel {
        ValueModel(
            id: id,
            name: name,
            description: description,
            tags: tags,
            category: category,
            displayState: displayState,
            photoId: photoId,
            photos: photos,
            entries: entries,
            parentId: parentId,
            diceId: diceId,
            groupId: groupId
        )
    }
}
