// @copyright André Trettin

import CoreRPG
import Foundation
import Observation

struct TableGenerationLink: Equatable, Hashable, Sendable {
    let itemId: UUID
    let name: String
}

struct TableGenerationEntry: Identifiable, Equatable, Hashable, Sendable {
    let id: UUID
    let name: String
    let content: String
    let tableLinks: [TableGenerationLink]
}

@MainActor @Observable
final class TableGenerationOccurrence: Identifiable {
    init(
        id: UUID = UUID(),
        tableId: UUID,
        tableName: String,
        tableType: TableModel.TableType,
        diceId: UUID?,
        entries: [TableGenerationEntry],
        depth: Int,
        tablePath: [UUID]
    ) {
        self.id = id
        self.tableId = tableId
        self.tableName = tableName
        self.tableType = tableType
        self.diceId = diceId
        self.entries = entries
        self.depth = depth
        self.tablePath = tablePath
    }

    let id: UUID
    let tableId: UUID
    let tableName: String
    let tableType: TableModel.TableType
    let diceId: UUID?
    let entries: [TableGenerationEntry]
    let depth: Int
    let tablePath: [UUID]

    var selectedEntryId: UUID?
    var children: [TableGenerationOccurrence] = []
    var ignoredCycleNames: [String] = []
    var lastRoll: Int?
    var awaitingPlayerId: UUID?
    var awaitingPlayerName: String?

    var selectedEntry: TableGenerationEntry? {
        guard let selectedEntryId else { return nil }
        return entries.first { $0.id == selectedEntryId }
    }

    var visibleEntries: [TableGenerationEntry] {
        if let selectedEntry {
            [selectedEntry]
        } else {
            entries
        }
    }
}

@MainActor @Observable
final class TableGenerationModel: Identifiable {
    init(id: UUID = UUID(), root: TableGenerationOccurrence) {
        self.id = id
        self.root = root
    }

    let id: UUID
    let root: TableGenerationOccurrence
    var errorMessage: String?

    var occurrences: [TableGenerationOccurrence] {
        flattened(root)
    }

    var canConfirm: Bool {
        let currentOccurrences = occurrences
        return !currentOccurrences.isEmpty
            && currentOccurrences.allSatisfy { $0.selectedEntry != nil }
    }

    var summary: ItemGenerationSummary? {
        guard canConfirm else { return nil }
        let selected = occurrences.compactMap { occurrence -> ItemGenerationSelection? in
            guard let entry = occurrence.selectedEntry else { return nil }
            let plainContent = entry.content.withoutLink()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let fallback = entry.name.withoutLink()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return ItemGenerationSelection(
                id: occurrence.id,
                tableId: occurrence.tableId,
                tableName: occurrence.tableName.withoutLink(),
                entryId: entry.id,
                entryName: entry.name.withoutLink(),
                content: plainContent.isEmpty ? fallback : plainContent
            )
        }
        guard !selected.isEmpty else { return nil }

        let value: String
        if selected.count == 1 {
            value = selected[0].content
        } else {
            value = selected.map { "\($0.tableName): \($0.content)" }
                .joined(separator: "\n")
        }
        return ItemGenerationSummary(
            name: root.tableName.withoutLink(),
            value: value,
            selections: selected
        )
    }

    func occurrence(id: UUID) -> TableGenerationOccurrence? {
        occurrences.first { $0.id == id }
    }

    private func flattened(
        _ occurrence: TableGenerationOccurrence
    ) -> [TableGenerationOccurrence] {
        [occurrence] + occurrence.children.flatMap(flattened)
    }
}
