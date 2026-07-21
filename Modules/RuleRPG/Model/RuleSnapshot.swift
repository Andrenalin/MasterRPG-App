// @copyright André Trettin

import CoreRPG
import Foundation

/// The only representation of a Rule that crosses a Core Data context boundary.
struct RuleSnapshot: Sendable, Identifiable {
    let id: UUID
    let name: CRDT<String>
    let description: CRDT<String>
    let tags: CRDT<[String]>
    let category: CRDT<ItemListCategory>
    let displayState: Int
    let entries: CRDTDataUpdate<[RuleEntryModel]>
    let sourceMetadata: CRDT<RuleSourceMetadata>
    let sourcePayload: CRDT<RuleSourcePayload?>
    let parentId: UUID?
}

extension RuleSnapshot {
    @MainActor
    init(_ model: RuleModel) {
        id = model.id
        name = model.name_
        description = model.description_
        tags = model.tags_
        category = model.category_
        displayState = model.displayState
        entries = model.entries_
        sourceMetadata = model.sourceMetadata_
        sourcePayload = model.sourcePayload_
        parentId = model.parentId
    }

    @MainActor
    func makeModel() -> RuleModel {
        RuleModel(
            id: id,
            name: name,
            description: description,
            tags: tags,
            category: category,
            displayState: displayState,
            entries: entries,
            sourceMetadata: sourceMetadata,
            sourcePayload: sourcePayload,
            parentId: parentId
        )
    }
}
