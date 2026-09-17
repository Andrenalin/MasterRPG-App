// @copyright André Trettin

import CoreRPG
import Foundation

// Split out of TableModel.swift: ItemDiffComparable (merge/isSame/version),
// Codable, ItemDataAccessable, ItemDuplicatable, ItemReferencable, and their
// canonical-content helper types — the CRDT/Codable/CoreData-snapshot
// persistence boilerplate. See CODE_AUDIT_Table §9.10.

extension TableModel: nonisolated ItemDiffComparable {
    nonisolated public func merge(_ other: TableModel) -> TableModel {
        return assumeMainActorIsolated {
            let mergedCategory = category_.merged(other: other.category_)
            let mergedEntries: CRDTDataUpdate<[TableEntryModel]>
            if mergedCategory.wrappedValue == .folder {
                // O(1) id -> entry lookups instead of a linear scan per id.
                // See CODE_AUDIT_Table §7.1.
                let ownById = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                let otherById = Dictionary(other.entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                let allIds = Set(ownById.keys).union(otherById.keys)
                let combined = allIds
                    .compactMap { id in ownById[id] ?? otherById[id] }
                    .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
                mergedEntries = CRDTDataUpdate(wrappedValue: combined)
            } else {
                mergedEntries = entries_.merged(other: other.entries_)
            }
            return TableModel(
                id: id,
                name: name_.merged(other: other.name_),
                description: description_.merged(other: other.description_),
                tags: tags_.merged(other: other.tags_),
                category: mergedCategory,
                displayState: other.displayState,
                tableType: tableType_.merged(other: other.tableType_),
                diceId: diceId_.merged(other: other.diceId_),
                entries: mergedEntries,
                diceResult: other.diceResult,
                parentId: other.parentId
            )

        }
    }

    nonisolated public func isSame(_ other: TableModel) -> Bool {
        return assumeMainActorIsolated {
            name == other.name &&
            description == other.description &&
            tags == other.tags &&
            category == other.category &&
            tableType == other.tableType &&
            diceId == other.diceId &&
            entries_.update == other.entries_.update &&
            parentId == other.parentId &&
            // sanity checks
            entries.count == other.entries.count &&
            entries.enumerated().allSatisfy { index, entry in
                entry == other.entries[index]
            }

        }
    }

    /// Deterministic identity of the Table content sent by the game master.
    /// Dice results are presentation-only game state and must not force a new
    /// package version when somebody rolls the same Table.
    public var version: Int {
        StableVersionDigest.digest(CanonicalTableContent(self))
    }
}

private struct CanonicalTableContent: Codable, Sendable {
    let id: UUID
    let name: String
    let description: String
    let tags: [String]
    let category: ItemListCategory
    let displayState: Int
    let tableType: TableModel.TableType
    let diceId: UUID?
    let entries: [CanonicalTableEntry]
    let parentId: UUID?

    @MainActor
    init(_ model: TableModel) {
        id = model.id
        name = model.name
        description = model.description
        tags = model.tags
        category = model.category
        displayState = model.displayState
        tableType = model.tableType
        diceId = model.diceId
        entries = model.entries.map(CanonicalTableEntry.init)
        parentId = model.parentId
    }
}

private struct CanonicalTableEntry: Codable, Sendable {
    let id: UUID
    let name: String
    let content: String
    let displayState: Int

    init(_ entry: TableEntryModel) {
        id = entry.id
        name = entry.name
        content = entry.content
        displayState = entry.displayState
    }
}

// MARK: - Review Properties

extension TableModel {
    @MainActor public var reviewProperties: [ReviewCustomProperty] {
        [
            ReviewCustomProperty(displayName: String(localized: "Table Type", bundle: .module)) {
                .option("\(($0 as? TableModel)?.tableType ?? TableType.list)")
            },
            ReviewCustomProperty(displayName: String(localized: "Dice", bundle: .module)) {
                ReviewPropertyValue(diceId: ($0 as? TableModel)?.diceId)
            }
        ]
    }
}

extension TableModel: nonisolated ItemDuplicatable {
    nonisolated public func duplicate() -> TableModel {
        return assumeMainActorIsolated {
            let copyName = duplicateName(from: name)
            return TableModel(id: UUID(), name: copyName, description: description, tags: tags, category: category, displayState: displayState, tableType: tableType, diceId: diceId, entries: entries.map { $0.duplicate() }, parentId: nil)
        }
    }
}

extension TableModel: nonisolated ItemReferencable {}

extension TableModel: nonisolated Equatable, nonisolated Hashable {
    nonisolated public static func == (lhs: TableModel, rhs: TableModel) -> Bool {
        return assumeMainActorIsolated {
            lhs.id == rhs.id && lhs.isSame(rhs) && lhs.displayState == rhs.displayState

        }
    }

    nonisolated public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
