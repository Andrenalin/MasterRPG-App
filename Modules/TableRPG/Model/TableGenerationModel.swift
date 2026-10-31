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
        // Not a trapping `uniqueKeysWithValues`: a peer or imported table can repeat an entry
        // id. See CODE_AUDIT_21 §6.8.
        self.selectionIds = Dictionary(
            entries.map { ($0.id, UUID()) },
            uniquingKeysWith: { first, _ in first }
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

    /// This occurrence and every occurrence below it.
    var occurrenceCount: Int {
        children.reduce(1) { $0 + $1.occurrenceCount }
    }
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

    /// Stricter than `isResolved`: for a multi-select table, every entry
    /// needs an explicit decision (selected or hidden) — not just one pick
    /// — before the generated text is considered settled enough to edit.
    var isFullyDecided: Bool {
        guard !entries.isEmpty else { return false }
        if allowsMultipleSelection {
            return entries.allSatisfy {
                selectedEntryIds.contains($0.id) || hiddenEntryIds.contains($0.id)
            }
        }
        return isResolved
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

    /// User-typed override of the generated outcome text. Offered once
    /// `isFullyDecided` so the result can be hand-finalized before
    /// confirming; `nil` while the computed outcome should still be shown.
    /// Populated by flattening `outcomeEditingSession`'s entries once the
    /// user leaves the sheet editor (see `TableGenerationController.endEditingOutcomeSheet(model:)`).
    var editedOutcome: String?

    /// The in-memory-only sheet-editing session backing the "Edit as Sheet"
    /// outcome editor, created once the user first opens it
    /// (`TableGenerationController.beginEditingOutcomeSheet(model:)`) and
    /// reused across Back/re-open cycles within this generation session —
    /// nothing here ever touches Core Data or CloudKit.
    var outcomeEditingSession: SimpleSheetEditingSession?

    /// Whether the rich sheet editor is currently shown in place of the
    /// occurrence selection tree.
    var isEditingOutcomeSheet = false

    var occurrences: [TableGenerationOccurrence] {
        flattened(root)
    }

    var canConfirm: Bool {
        let currentOccurrences = occurrences
        return !currentOccurrences.isEmpty
            && currentOccurrences.allSatisfy(\.isResolved)
    }

    /// True once every occurrence has an explicit decision for every entry.
    /// Stricter than `canConfirm` (which only needs one pick per table) —
    /// this gates when the outcome preview expands into an editable field.
    var isFullyDecided: Bool {
        let currentOccurrences = occurrences
        return !currentOccurrences.isEmpty
            && currentOccurrences.allSatisfy(\.isFullyDecided)
    }

    var summary: ItemGenerationSummary? {
        guard canConfirm else { return nil }
        let selected = currentSelections
        guard !selected.isEmpty else { return nil }
        return ItemGenerationSummary(
            // The sheet's own root header can't be edited in place, but its
            // first entry can (see `TableGenerationController.beginEditingOutcomeSheet(model:)`)
            // — that's the editable "title" for both Save and Send, once the
            // sheet editor has been opened; before that, or if it never was,
            // this just falls back to the root table's name.
            name: outcomeEditingSession?.currentModel?.entries.first?.name ?? root.tableName.withoutLink(),
            value: editedOutcome ?? combinedValue(for: selected),
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

    /// Also used by `TableGenerationController.beginEditingOutcomeSheet(model:)`
    /// to seed the outcome sheet editor with one entry row per selection.
    var currentSelections: [ItemGenerationSelection] {
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
