// @copyright André Trettin

import CoreRPG
import Foundation

/// Sendable value snapshot of a AdventureModel — the only representation that crosses
/// the Core Data context boundary. Not Codable: the .gmz wire format stays on
/// AdventureModel's Codable implementation.
struct AdventureSnapshot: Sendable, Identifiable {
    let id: UUID
    let name: CRDT<String>
    let description: CRDT<String>
    let tags: CRDT<[String]>
    let category: CRDT<ItemListCategory>
    let displayState: Int
    let photoId: CRDT<UUID?>
    let diceId: UUID?
    let entries: CRDTDataUpdate<[AdventureEntryModel]>
    let parentId: UUID?
}

extension AdventureSnapshot {
    @MainActor
    init(_ model: AdventureModel) {
        id = model.id
        name = model.name_
        description = model.description_
        tags = model.tags_
        category = model.category_
        displayState = model.displayState
        photoId = model.photoId_
        diceId = model.diceId
        entries = model.entries_
        parentId = model.parentId
    }

    @MainActor
    func makeModel() -> AdventureModel {
        AdventureModel(
            id: id,
            name: name,
            description: description,
            tags: tags,
            category: category,
            displayState: displayState,
            photoId: photoId,
            diceId: diceId,
            entries: entries,
            parentId: parentId
        )
    }
}
