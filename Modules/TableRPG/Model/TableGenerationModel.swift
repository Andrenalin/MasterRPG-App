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
        tablePath: [UUID],
        sourceEntryId: UUID? = nil
    ) {
        self.id = id
        self.tableId = tableId
        self.tableName = tableName
        self.tableType = tableType
        self.diceId = diceId
        self.entries = entries
        self.depth = depth
        self.tablePath = tablePath
        self.sourceEntryId = sourceEntryId
        self.selectionIds = Dictionary(
            uniqueKeysWithValues: entries.map { ($0.id, UUID()) }
        )
    }

    let id: UUID
    let tableId: UUID
    let tableName: String
    let tableType: TableModel.TableType
    let diceId: UUID?
    let entries: [TableGenerationEntry]
    let depth: Int
    let tablePath: [UUID]
    /// The id of the entry (in the parent occurrence) whose table link
    /// generated this occurrence — `nil` for the root occurrence. Used to
    /// nest this occurrence's UI directly under that entry instead of after
    /// the whole parent table.
    let sourceEntryId: UUID?

    @ObservationIgnored private let selectionIds: [UUID: UUID]

    var selectedEntryIds: Set<UUID> = []
    var hiddenEntryIds: Set<UUID> = []
    var children: [TableGenerationOccurrence] = []
    var ignoredCycleNames: [String] = []
    var lastRoll: Int?
    var isAwaitingPlayerRoll = false
    var awaitingPlayerId: UUID?
    var awaitingPlayerName: String?

    var allowsMultipleSelection: Bool {
        diceId == nil
    }

    var selectedEntryId: UUID? {
        get { selectedEntries.first?.id }
        set {
            if let newValue {
                selectedEntryIds = [newValue]
            } else {
                selectedEntryIds = []
            }
        }
    }

    var selectedEntry: TableGenerationEntry? {
        selectedEntries.first
    }

    var selectedEntries: [TableGenerationEntry] {
        entries.filter { selectedEntryIds.contains($0.id) }
    }

    var visibleEntries: [TableGenerationEntry] {
        if allowsMultipleSelection {
            entries.filter { !hiddenEntryIds.contains($0.id) }
        } else if let selectedEntry {
            [selectedEntry]
        } else {
            entries
        }
    }

    var isResolved: Bool {
        guard !entries.isEmpty, !selectedEntryIds.isEmpty else { return false }
        if allowsMultipleSelection {
            return true
        }
        return selectedEntryIds.count == 1
    }

    var hasDecisions: Bool {
        !selectedEntryIds.isEmpty
            || !hiddenEntryIds.isEmpty
            || lastRoll != nil
            || isAwaitingPlayerRoll
    }

    func selectionId(for entryId: UUID) -> UUID {
        selectionIds[entryId] ?? entryId
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
            && currentOccurrences.allSatisfy(\.isResolved)
    }

    var summary: ItemGenerationSummary? {
        guard canConfirm else { return nil }
        let selected = currentSelections
        guard !selected.isEmpty else { return nil }
        return ItemGenerationSummary(
            name: root.tableName.withoutLink(),
            value: combinedValue(for: selected),
            selections: selected
        )
    }

    /// A live preview of the outcome built from whatever has been selected
    /// so far, updating with every choice even before every table is resolved.
    var currentOutcome: String? {
        let selected = currentSelections
        guard !selected.isEmpty else { return nil }
        return combinedValue(for: selected)
    }

    func occurrence(id: UUID) -> TableGenerationOccurrence? {
        occurrences.first { $0.id == id }
    }

    private var currentSelections: [ItemGenerationSelection] {
        occurrences.flatMap { occurrence in
            occurrence.selectedEntries.map { entry in
                ItemGenerationSelection(
                    id: occurrence.selectionId(for: entry.id),
                    tableId: occurrence.tableId,
                    tableName: occurrence.tableName.withoutLink(),
                    entryId: entry.id,
                    entryName: entry.name.withoutLink(),
                    content: displayContent(for: entry)
                )
            }
        }
    }

    private func displayContent(for entry: TableGenerationEntry) -> String {
        let plainContent = entry.content.withoutLink()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !plainContent.isEmpty { return plainContent }
        return entry.name.withoutLink()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A single selection is shown as its raw content. Once more than one
    /// choice contributes to the outcome, the text mirrors the on-screen
    /// nesting: an entry's own nested generation is appended to it with
    /// " / " (instead of a separate line), and sibling entries selected in
    /// the same table are joined with ", " under one table-name prefix.
    private func combinedValue(for selections: [ItemGenerationSelection]) -> String {
        if selections.count == 1 {
            return selections[0].content
        }
        return "\(root.tableName.withoutLink()): \(lineage(for: root))"
    }

    private func lineage(for occurrence: TableGenerationOccurrence) -> String {
        occurrence.selectedEntries.map { entry in
            var text = displayContent(for: entry)

            let childLineages = occurrence.children
                .filter { $0.sourceEntryId == entry.id }
                .map { lineage(for: $0) }
                .filter { !$0.isEmpty }
            if !childLineages.isEmpty {
                text += " / " + childLineages.joined(separator: " / ")
            }
            return text
        }
        .joined(separator: ", ")
    }

    private func flattened(
        _ occurrence: TableGenerationOccurrence
    ) -> [TableGenerationOccurrence] {
        [occurrence] + occurrence.children.flatMap(flattened)
    }
}
