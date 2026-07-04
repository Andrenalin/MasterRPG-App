// @copyright André Trettin

import CoreRPG
import Foundation

/// Sendable value snapshot of a PhotoModel — the only representation that crosses
/// the Core Data context boundary. Not Codable: the .gmz wire format stays on
/// PhotoModel's Codable implementation.
struct PhotoSnapshot: Sendable, Identifiable {
    let id: UUID
    let name: CRDT<String>
    let description: CRDT<String>
    let tags: CRDT<[String]>
    let category: CRDT<ItemListCategory>
    let displayState: Int
    let degrees: CRDT<Double>
    let fileUrl: CRDTDataUpdate<FileUrl?>
    let entries: CRDTDataUpdate<[PhotoEntryModel]>
    let parentId: UUID?
}

extension PhotoSnapshot {
    @MainActor
    init(_ model: PhotoModel) {
        id = model.id
        name = model.name_
        description = model.description_
        tags = model.tags_
        category = model.category_
        displayState = model.displayState
        degrees = model.degrees_
        fileUrl = model.fileUrl_
        entries = model.entries_
        parentId = model.parentId
    }

    @MainActor
    func makeModel() -> PhotoModel {
        PhotoModel(
            id: id,
            name: name,
            description: description,
            tags: tags,
            category: category,
            displayState: displayState,
            degrees: degrees,
            fileUrl: fileUrl,
            entries: entries,
            parentId: parentId
        )
    }
}
