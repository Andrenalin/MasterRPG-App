// @copyright André Trettin

import CoreRPG
import Foundation

/// Sendable value snapshot of a GeneratorModel — the only representation that crosses
/// the Core Data context boundary. Not Codable: the .gmz wire format stays on
/// GeneratorModel's Codable implementation.
struct GeneratorSnapshot: Sendable, Identifiable {
    let id: UUID
    let name: CRDT<String>
    let description: CRDT<String>
    let tags: CRDT<[String]>
    let category: CRDT<ItemListCategory>
    let displayState: Int
    let entries: CRDTDataUpdate<[ChildEntryModel]>
    let parentId: UUID?
    let genType: GeneratorModel.GenType
    let referenceId: UUID?
}

extension GeneratorSnapshot {
    @MainActor
    init(_ model: GeneratorModel) {
        id = model.id
        name = model.name_
        description = model.description_
        tags = model.tags_
        category = model.category_
        displayState = model.displayState
        entries = model.entries_
        parentId = model.parentId
        genType = model.genType
        referenceId = model.referenceId
    }

    @MainActor
    func makeModel() -> GeneratorModel {
        GeneratorModel(
            id: id,
            name: name,
            description: description,
            tags: tags,
            category: category,
            displayState: displayState,
            entries: entries,
            parentId: parentId,
            genType: genType,
            referenceId: referenceId
        )
    }
}
