// @copyright André Trettin

import CoreRPG
import Foundation

/// Sendable value snapshot of an AudioModel — the only representation that crosses
/// the Core Data context boundary. Not Codable: the .gmz wire format stays on
/// AudioModel's Codable implementation.
struct AudioSnapshot: Sendable, Identifiable {
    let id: UUID
    let name: CRDT<String>
    let description: CRDT<String>
    let tags: CRDT<[String]>
    let category: CRDT<ItemListCategory>
    let displayState: Int
    let fileUrl: CRDTDataUpdate<FileUrl?>
    let entries: CRDTDataUpdate<[AudioEntryModel]>
    let parentId: UUID?
}

extension AudioSnapshot {
    @MainActor
    init(_ model: AudioModel) {
        id = model.id
        name = model.name_
        description = model.description_
        tags = model.tags_
        category = model.category_
        displayState = model.displayState
        fileUrl = model.fileUrl_
        entries = model.entries_
        parentId = model.parentId
    }

    @MainActor
    func makeModel() -> AudioModel {
        AudioModel(
            id: id,
            name: name,
            description: description,
            tags: tags,
            category: category,
            displayState: displayState,
            fileUrl: fileUrl,
            entries: entries,
            parentId: parentId
        )
    }
}
