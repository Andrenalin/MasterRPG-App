// @copyright André Trettin

import CoreRPG
import Foundation

/// Sendable value snapshot of a TableModel — the only representation that crosses
/// the Core Data context boundary. Not Codable: the .gmz wire format stays on
/// TableModel's Codable implementation.
struct TableSnapshot: Sendable, Identifiable {
    let id: UUID
    let name: CRDT<String>
    let description: CRDT<String>
    let tags: CRDT<[String]>
    let category: CRDT<ItemListCategory>
    let displayState: Int
    let tableType: CRDT<TableModel.TableType>
    let diceId: CRDT<UUID?>
    let entries: CRDTDataUpdate<[TableEntryModel]>
    let parentId: UUID?
}

extension TableSnapshot {
    @MainActor
    init(_ model: TableModel) {
        id = model.id
        name = model.name_
        description = model.description_
        tags = model.tags_
        category = model.category_
        displayState = model.displayState
        tableType = model.tableType_
        diceId = model.diceId_
        entries = model.entries_
        parentId = model.parentId
    }

    @MainActor
    func makeModel() -> TableModel {
        TableModel(
            id: id,
            name: name,
            description: description,
            tags: tags,
            category: category,
            displayState: displayState,
            tableType: tableType,
            diceId: diceId,
            entries: entries,
            parentId: parentId
        )
    }
}
