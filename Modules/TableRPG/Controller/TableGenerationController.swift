// @copyright André Trettin

import CoreRPG
import DiceRPG
import Foundation

struct TableGenerationController: Sendable {
    let itemController: ItemController
    let diceRoot: DiceRootModel

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

        rebuildChildren(in: occurrence)
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
        model.errorMessage = nil
        occurrence.selectedEntryIds = []
        occurrence.hiddenEntryIds = []
        occurrence.children = []
        occurrence.ignoredCycleNames = []
        occurrence.lastRoll = nil
        clearPendingRoll(in: occurrence)
    }

    @MainActor
    func autoRoll(model: TableGenerationModel) {
        model.errorMessage = nil
        autoRoll(occurrence: model.root, model: model)
    }

    @MainActor
    func apply(
        result: Int,
        to occurrence: TableGenerationOccurrence,
        model: TableGenerationModel
    ) {
        model.errorMessage = nil
        guard let entry = matchingEntry(for: result, in: occurrence) else {
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
            rebuildChildren(in: occurrence)
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
        let trimmed = name
            .trimmingCharacters(in: CharacterSet(charactersIn: "*`[]() "))
        let prefix = trimmed.prefix {
            $0.isNumber || $0.isWhitespace || $0 == "-" || $0 == "–" || $0 == "—"
        }
        let values = prefix.split { !$0.isNumber }.compactMap { Int($0) }
        guard let first = values.first else { return nil }
        let last = values.dropFirst().first ?? first
        return min(first, last)...max(first, last)
    }

    @MainActor
    func matchingEntry(
        for result: Int,
        in occurrence: TableGenerationOccurrence
    ) -> TableGenerationEntry? {
        if let ranged = occurrence.entries.first(where: {
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
        model: TableGenerationModel
    ) {
        if !occurrence.isResolved {
            guard roll(occurrence: occurrence, model: model) != nil else {
                return
            }
        }

        for child in occurrence.children {
            autoRoll(occurrence: child, model: model)
        }
    }

    @MainActor
    private func rebuildChildren(
        in occurrence: TableGenerationOccurrence
    ) {
        // Reuse an already-selected entry's existing child occurrence
        // instead of recreating it, so toggling a sibling selection in a
        // multi-select table doesn't discard the choices already made
        // inside that entry's generated table.
        let existingChildren = occurrence.children
        var newChildren: [TableGenerationOccurrence] = []
        occurrence.ignoredCycleNames = []

        for entry in occurrence.selectedEntries {
            for link in entry.tableLinks {
                if occurrence.tablePath.contains(link.itemId) {
                    occurrence.ignoredCycleNames.append(link.name)
                    continue
                }
                if let existing = existingChildren.first(where: {
                    $0.sourceEntryId == entry.id && $0.tableId == link.itemId
                }) {
                    newChildren.append(existing)
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
                    tableLinks: $0.links(for: $0.content)
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
