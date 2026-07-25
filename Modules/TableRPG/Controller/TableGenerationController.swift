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
        occurrence.awaitingPlayerId = nil
        occurrence.awaitingPlayerName = nil

        if occurrence.selectedEntryId == entryId {
            occurrence.selectedEntryId = nil
            occurrence.children = []
            occurrence.ignoredCycleNames = []
            return
        }

        guard let entry = occurrence.entries.first(where: { $0.id == entryId }) else {
            return
        }
        occurrence.selectedEntryId = entryId
        occurrence.children = []
        occurrence.ignoredCycleNames = []

        for link in entry.tableLinks {
            if occurrence.tablePath.contains(link.itemId) {
                occurrence.ignoredCycleNames.append(link.name)
                continue
            }
            if let child = makeOccurrence(
                tableId: link.itemId,
                depth: occurrence.depth + 1,
                tablePath: occurrence.tablePath
            ) {
                occurrence.children.append(child)
            }
        }
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
        guard let entry = matchingEntry(for: result, in: occurrence) else {
            model.errorMessage = String(
                localized: "Roll \(result) does not match an entry in \(occurrence.tableName).",
                bundle: .module
            )
            return
        }
        select(entryId: entry.id, in: occurrence, model: model)
        occurrence.lastRoll = result
        occurrence.awaitingPlayerId = nil
        occurrence.awaitingPlayerName = nil
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
        if occurrence.selectedEntry == nil {
            let result: Int
            if let diceId = occurrence.diceId {
                result = diceRoot.role(diceId: diceId)
            } else {
                guard !occurrence.entries.isEmpty else {
                    model.errorMessage = String(
                        localized: "\(occurrence.tableName) has no entries.",
                        bundle: .module
                    )
                    return
                }
                result = diceRoot.role(number: occurrence.entries.count)
            }
            apply(result: result, to: occurrence, model: model)
        }

        for child in occurrence.children {
            autoRoll(occurrence: child, model: model)
        }
    }

    @MainActor
    private func makeOccurrence(
        tableId: UUID,
        depth: Int,
        tablePath: [UUID]
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
            tablePath: tablePath + [table.id]
        )
    }
}
