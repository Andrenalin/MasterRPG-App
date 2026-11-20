// @copyright André Trettin

import CoreRPG
import DiceRPG
import Foundation

/// Breaks the construction-order cycle: `TableGenerationController` is
/// built inside `TableRootModel.init()`, before `TableRootModel.setUp(...)`
/// runs — which is when the real, whole-app `RootManager` (with every
/// module's real root, not this feature's own throwaway `SimpleSheetEditingSession`
/// one) becomes available. `TableRootModel.setUp(...)` fills this in.
@MainActor
final class TableGenerationRootManagerBox: Sendable {
    var rootManager: RootManager?
    /// Tells Siri about an "Auto Roll" of a table (`TableRootModel.donateRoll(of:)`); set up with
    /// the root manager. See CODE_AUDIT_AppIntents3 §4.7.
    var donateRoll: (@MainActor (UUID) -> Void)?
}

struct TableGenerationController: Sendable {
    /// A table may legitimately link back to a table already in its own
    /// ancestry — e.g. a random encounter table rolling on itself again is a
    /// normal, intentional loop, not malformed data — so only genuinely
    /// runaway recursion needs stopping, not the first repeat. Mirrors
    /// `RecursionLimits.maxValueLinkDepth` in CharacterRPG, the same guard
    /// against a link chain recursing indefinitely.
    static let maxTableRecursionCount = 10

    /// The most table occurrences one generation holds. The depth limit above bounds a path, not
    /// the tree: a table whose entries each link a few tables (itself included) multiplies at
    /// every level and reaches millions of nodes within ten levels. A link that would go beyond
    /// the cap is skipped like a recursive one. See CODE_AUDIT_22 §5.7.
    static let maxOccurrenceCount = 500

    let itemController: ItemController
    let diceRoot: DiceRootModel
    let rootManagerBox: TableGenerationRootManagerBox

    @MainActor
    func makeModel(itemId: UUID) -> TableGenerationModel {
        let root = makeOccurrence(
            tableId: itemId,
            depth: 0,
            tablePath: []
        ) ?? TableGenerationOccurrence(
            tableId: itemId,
            tableName: String(localized: "Unknown Table", bundle: .module),
            tableType: .list,
            diceId: nil,
            entries: [],
            depth: 0,
            tablePath: [itemId]
        )
        let model = TableGenerationModel(root: root)
        if root.entries.isEmpty {
            model.errorMessage = String(
                localized: "This table has no entries to generate.",
                bundle: .module
            )
        }
        return model
    }

    @MainActor
    func select(
        entryId: UUID,
        in occurrence: TableGenerationOccurrence,
        model: TableGenerationModel
    ) {
        discardOutcomeSession(model: model)
        model.errorMessage = nil
        occurrence.lastRoll = nil
        clearPendingRoll(in: occurrence)

        guard occurrence.entries.contains(where: { $0.id == entryId }),
              !occurrence.hiddenEntryIds.contains(entryId)
        else {
            return
        }

        if occurrence.allowsMultipleSelection {
            if occurrence.selectedEntryIds.contains(entryId) {
                occurrence.selectedEntryIds.remove(entryId)
            } else {
                occurrence.selectedEntryIds.insert(entryId)
            }
        } else if occurrence.selectedEntryIds.contains(entryId) {
            occurrence.selectedEntryIds = []
        } else {
            occurrence.selectedEntryIds = [entryId]
        }

        rebuildChildren(in: occurrence, model: model)
    }

    @MainActor
    func canHide(
        entryId: UUID,
        in occurrence: TableGenerationOccurrence
    ) -> Bool {
        guard occurrence.allowsMultipleSelection,
              occurrence.visibleEntries.contains(where: { $0.id == entryId }),
              !occurrence.selectedEntryIds.contains(entryId)
        else {
            return false
        }
        return !occurrence.selectedEntryIds.isEmpty
            || occurrence.visibleEntries.count > 1
    }

    @MainActor
    func hide(
        entryId: UUID,
        in occurrence: TableGenerationOccurrence,
        model: TableGenerationModel
    ) {
        guard canHide(entryId: entryId, in: occurrence) else { return }
        discardOutcomeSession(model: model)
        model.errorMessage = nil
        occurrence.lastRoll = nil
        clearPendingRoll(in: occurrence)
        occurrence.hiddenEntryIds.insert(entryId)
    }

    @MainActor
    func reset(
        occurrence: TableGenerationOccurrence,
        model: TableGenerationModel
    ) {
        discardOutcomeSession(model: model)
        model.errorMessage = nil
        occurrence.selectedEntryIds = []
        occurrence.hiddenEntryIds = []
        occurrence.children = []
        occurrence.ignoredCycleNames = []
        occurrence.truncatedLinkNames = []
        occurrence.lastRoll = nil
        clearPendingRoll(in: occurrence)
    }

    @MainActor
    /// `donates` is off for `RollTableIntent`: the system already knows about its own runs.
    func autoRoll(model: TableGenerationModel, donates: Bool = true) {
        model.errorMessage = nil
        // Each roll clears the message, so the first failure is kept here and shown at the end:
        // a later successful sibling must not erase it. See CODE_AUDIT_23 §5.19.
        var firstError: String?
        autoRoll(occurrence: model.root, model: model, firstError: &firstError)
        model.errorMessage = firstError
        if donates {
            rootManagerBox.donateRoll?(model.root.tableId)
        }
    }

    @MainActor
    func apply(
        result: Int,
        to occurrence: TableGenerationOccurrence,
        model: TableGenerationModel
    ) {
        discardOutcomeSession(model: model)
        model.errorMessage = nil
        guard let entry = matchingEntry(for: result, in: occurrence) else {
            // Clear a stale badge from a previous successful roll so it
            // doesn't linger next to this failure message. See
            // CODE_AUDIT_Table §5.3.
            occurrence.lastRoll = nil
            clearPendingRoll(in: occurrence)
            model.errorMessage = String(
                localized: "Roll \(result) does not match an entry in \(occurrence.tableName).",
                bundle: .module
            )
            return
        }

        let newSelection: Set<UUID> = [entry.id]
        let selectionChanged = occurrence.selectedEntryIds != newSelection
        occurrence.selectedEntryIds = newSelection
        occurrence.hiddenEntryIds.remove(entry.id)
        if selectionChanged {
            rebuildChildren(in: occurrence, model: model)
        }
        occurrence.lastRoll = result
        clearPendingRoll(in: occurrence)
    }

    @discardableResult
    @MainActor
    func roll(
        occurrence: TableGenerationOccurrence,
        model: TableGenerationModel
    ) -> Int? {
        model.errorMessage = nil
        let result: Int
        if let diceId = occurrence.diceId {
            result = diceRoot.roll(diceId: diceId)
        } else {
            guard !occurrence.entries.isEmpty else {
                model.errorMessage = String(
                    localized: "\(occurrence.tableName) has no entries.",
                    bundle: .module
                )
                return nil
            }
            // A single-entry table has only one possible outcome. Rolling
            // through `RawDie` would go through `Sides.number()`'s clamp of
            // any side count below 2 up to 2 (avoiding a crashing
            // `Int.random(in: 1...0)`), giving a ~50% chance of a roll of 2
            // — which `matchingEntry` can't resolve since only index 0
            // exists, surfacing a confusing error for an otherwise
            // unremarkable single-entry table. See CODE_AUDIT §5.3.
            result = occurrence.entries.count == 1 ? 1 : diceRoot.roll(number: occurrence.entries.count)
        }
        apply(result: result, to: occurrence, model: model)
        return result
    }

    @MainActor
    func gameData(
        for occurrence: TableGenerationOccurrence,
        sessionId: UUID
    ) async throws -> NetworkCodableDataType {
        let category = ResultCategory(
            id: sessionId,
            childId: occurrence.id,
            module: .table
        )
        if let diceId = occurrence.diceId {
            return try await diceRoot.diceGameControllable.createGameData(
                for: diceId,
                resultCategory: category
            )
        }
        return try await diceRoot.diceGameControllable.createVirtualGameData(
            numberOfSides: max(occurrence.entries.count, 1),
            name: occurrence.tableName,
            resultCategory: category
        )
    }

    func selectorRange(for name: String) -> ClosedRange<Int>? {
        TableRollRange.selectorRange(for: name)
    }

    @MainActor
    func matchingEntry(
        for result: Int,
        in occurrence: TableGenerationOccurrence
    ) -> TableGenerationEntry? {
        // Ranges belong to a dice table: one with a linked Dice (the editor never sets
        // `tableType`, so the Dice link is what makes a user-made table a dice table) or an
        // imported one typed `.dice`. A table without a Dice is rolled by position, and a leading
        // number in an entry name ("2 Wolves") is not a range there: read as one, "5 Orcs" could
        // never be rolled. See CODE_AUDIT_21 §5.18 and CODE_AUDIT §5.3.
        let isDiceTable = occurrence.diceId != nil || occurrence.tableType == .dice
        if isDiceTable, let ranged = occurrence.entries.first(where: {
            selectorRange(for: $0.name)?.contains(result) == true
        }) {
            return ranged
        }
        let index = result - 1
        guard occurrence.entries.indices.contains(index) else { return nil }
        return occurrence.entries[index]
    }

    @MainActor
    private func autoRoll(
        occurrence: TableGenerationOccurrence,
        model: TableGenerationModel,
        firstError: inout String?
    ) {
        if !occurrence.isResolved {
            let rolled = roll(occurrence: occurrence, model: model)
            if firstError == nil {
                firstError = model.errorMessage
            }
            guard rolled != nil else {
                return
            }
        }

        for child in occurrence.children {
            autoRoll(occurrence: child, model: model, firstError: &firstError)
        }
    }

    @MainActor
    private func rebuildChildren(
        in occurrence: TableGenerationOccurrence,
        model: TableGenerationModel
    ) {
        // Reuse an already-selected entry's existing child occurrence
        // instead of recreating it, so toggling a sibling selection in a
        // multi-select table doesn't discard the choices already made
        // inside that entry's generated table.
        // Each existing child is consumed once, so an entry that links the same table twice keeps
        // two distinct children instead of reusing the first for both. See CODE_AUDIT §5.8.
        var unusedChildren = occurrence.children
        var newChildren: [TableGenerationOccurrence] = []
        occurrence.ignoredCycleNames = []
        occurrence.truncatedLinkNames = []

        for entry in occurrence.selectedEntries {
            for link in entry.tableLinks {
                // Only ignore the link once this table has already recurred
                // `maxTableRecursionCount` times in its own ancestry — a
                // single repeat (e.g. Table A linking straight back to
                // itself) is a legitimate loop the player can keep rolling
                // on, not a cycle to break immediately.
                if occurrence.tablePath.count(where: { $0 == link.itemId }) >= Self.maxTableRecursionCount {
                    occurrence.ignoredCycleNames.append(link.name)
                    continue
                }
                if let existingIndex = unusedChildren.firstIndex(where: {
                    $0.sourceEntryId == entry.id && $0.tableId == link.itemId
                }) {
                    newChildren.append(unusedChildren.remove(at: existingIndex))
                    continue
                }
                // This occurrence's old children are replaced below, so they do not count.
                let kept = model.root.occurrenceCount - occurrence.children.reduce(0) { $0 + $1.occurrenceCount }
                    + newChildren.reduce(0) { $0 + $1.occurrenceCount }
                if kept >= Self.maxOccurrenceCount {
                    // Not a cycle: the generation reached its size limit. See CODE_AUDIT_23 §5.19.
                    occurrence.truncatedLinkNames.append(link.name)
                    continue
                }
                if let child = makeOccurrence(
                    tableId: link.itemId,
                    depth: occurrence.depth + 1,
                    tablePath: occurrence.tablePath,
                    sourceEntryId: entry.id
                ) {
                    newChildren.append(child)
                }
            }
        }

        occurrence.children = newChildren
    }

    @MainActor
    private func clearPendingRoll(
        in occurrence: TableGenerationOccurrence
    ) {
        occurrence.isAwaitingPlayerRoll = false
        occurrence.awaitingPlayerId = nil
        occurrence.awaitingPlayerName = nil
    }

    /// Same reset as `clearPendingRoll(in:)`, exposed for the view's
    /// share-failure recovery path so it doesn't hand-roll the controller's
    /// own state-reset logic. See CODE_AUDIT_Table §5.7.
    @MainActor
    func cancelPendingShare(in occurrence: TableGenerationOccurrence) {
        clearPendingRoll(in: occurrence)
    }

    @MainActor
    private func makeOccurrence(
        tableId: UUID,
        depth: Int,
        tablePath: [UUID],
        sourceEntryId: UUID? = nil
    ) -> TableGenerationOccurrence? {
        guard let table = itemController.itemSync(for: tableId),
              !table.specialCategory
        else {
            return nil
        }
        return TableGenerationOccurrence(
            tableId: table.id,
            tableName: table.name,
            tableType: table.tableType,
            diceId: table.diceId,
            entries: table.entries.map {
                TableGenerationEntry(
                    id: $0.id,
                    name: $0.name,
                    content: $0.content,
                    tableLinks: LinkReplaceController.links(for: $0.content)
                        .filter { $0.module == .table && $0.entryId == nil }
                        .map {
                            TableGenerationLink(
                                itemId: $0.itemId,
                                name: $0.name
                            )
                        }
                )
            },
            depth: depth,
            tablePath: tablePath + [table.id],
            sourceEntryId: sourceEntryId
        )
    }
}
