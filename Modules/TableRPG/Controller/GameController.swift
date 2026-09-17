// @copyright André Trettin

import CoreRPG
import DiceRPG
import Foundation

public protocol TableGameStorable: Sendable {
    @MainActor func addResult(
        _ result: ResultCategory,
        diceResult: DiceResultModel
    )
    @MainActor func isTableAvailable(itemId: UUID, version: Int) -> Bool
    func receiveTable(itemId: UUID, data: NetworkCodableDataType, makeCurrent: Bool) async throws -> Bool
}

@MainActor
private final class TableGameAvailabilityModel {
    private var availableVersions: [UUID: Int] = [:]

    func contains(itemId: UUID, version: Int) -> Bool {
        guard version != 0 else { return false }
        return availableVersions[itemId] == version
    }

    func markAvailable(itemId: UUID, version: Int) {
        guard version != 0 else { return }
        availableVersions[itemId] = version
    }

    func reset() {
        availableVersions.removeAll()
    }
}

/// Serializes `receiveTable` per `itemId` so its multi-`await` import/merge
/// sequence can no longer interleave with a concurrent call for the same
/// table (state like `previousIdentities`/`persistentTables` captured early
/// in one call could otherwise go stale before it's used, if the MainActor
/// ran a second `receiveTable` for the same item in between). Different
/// items still run fully concurrently. See CODE_AUDIT_Table §3.2.
@MainActor
private final class TableReceiveSerializer {
    private var tails: [UUID: (token: UUID, task: Task<Void, Never>)] = [:]

    func run<T: Sendable>(
        itemId: UUID,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let token = UUID()
        let previous = tails[itemId]?.task
        let gate = Task<Void, Never> {
            _ = await previous?.value
        }
        tails[itemId] = (token, gate)
        await gate.value
        defer {
            if tails[itemId]?.token == token {
                tails[itemId] = nil
            }
        }
        return try await operation()
    }
}

struct GameController: Sendable {
    @MainActor init(
        diceRoot: DiceRootModel,
        itemController: ItemController,
        exportController: ExportController,
        generationSessionStore: TableGenerationSessionStore
    ) {
        self.diceRoot = diceRoot
        self.itemController = itemController
        self.exportController = exportController
        self.generationSessionStore = generationSessionStore

        self.gameModel = ItemGameModel(itemDataModel: itemController.itemDataModel)
        self.tableGameAvailabilityModel = TableGameAvailabilityModel()
        self.receiveSerializer = TableReceiveSerializer()
    }

    let diceRoot: DiceRootModel
    let itemController: ItemController
    let exportController: ExportController
    let generationSessionStore: TableGenerationSessionStore

    let gameModel: ItemGameModel
    private let tableGameAvailabilityModel: TableGameAvailabilityModel
    private let receiveSerializer: TableReceiveSerializer

}

// gameItem(for:)/setGame(item:itemId:)/currentItem() come from
// ModuleGameControllable's default implementations. See CODE_AUDIT_Game §9.1.
extension GameController: ModuleGameControllable {}

extension GameController: GameControllable {
    var itemControllable: any ItemControllable { itemController as (any ItemControllable) }
    var exportControllable: any ExportControllable { exportController as ExportControllable }

    @MainActor
    func resetGameState() {
        tableGameAvailabilityModel.reset()
    }
}

extension GameController: TableGameStorable {
    @MainActor public func addResult(
        _ result: ResultCategory,
        diceResult: DiceResultModel
    ) {
        guard result.module == .table else { return }
        if generationSessionStore.consume(
            category: result,
            diceResult: diceResult
        ) {
            return
        }
        addResult(result, value: diceResult.values)
    }

    @MainActor
    func addResult(_ result: ResultCategory, value: String) {
        guard result.module == .table else { return }
        let model = gameItem(for: result.id)
        if let childId = result.childId {
             model[childId].diceResult = value
        } else {
            model.diceResult = value
        }
    }
    
    // Not currently called from production code (only from
    // GameControllerTests) — `TableGenerationController.matchingEntry`
    // handles live rolls instead. Kept in sync with it via the shared
    // `TableRollRange` parser so a future caller doesn't inherit a stale
    // implementation. See CODE_AUDIT_Table §5.1/§5.2/§5.8.
    @MainActor
    func entry(for id: UUID, with result: Int) -> UUID? {
        let item = gameItem(for: id)
        switch item.tableType {
        case .dice:
            guard item.diceId != nil else { return nil }
            if let ranged = item.entries.first(where: {
                TableRollRange.selectorRange(for: $0.name)?.contains(result) == true
            }) {
                return ranged.id
            }
            let index = result - 1
            guard item.entries.indices.contains(index) else { return nil }
            return item.entries[index].id
        case .list, .all:
            let index = result - 1
            if index >= 0 && index < item.entries.count {
                return item.entries[index].id
            }
            return nil
        }
    }

    @MainActor
    public func isTableAvailable(itemId: UUID, version: Int) -> Bool {
        tableGameAvailabilityModel.contains(itemId: itemId, version: version) &&
            gameModel.itemData[itemId] is TableModel
    }

    public func receiveTable(itemId: UUID, data: NetworkCodableDataType, makeCurrent: Bool) async throws -> Bool {
        try await receiveSerializer.run(itemId: itemId) {
            try await self.receiveTableSerialized(itemId: itemId, data: data, makeCurrent: makeCurrent)
        }
    }

    private func receiveTableSerialized(itemId: UUID, data: NetworkCodableDataType, makeCurrent: Bool) async throws -> Bool {
        guard data.type == .table, data.id == itemId else {
            throw ItemGameStorableError.wrongData
        }

        guard data.version != 0 else { return false }

        guard let encodedData = data.data else {
            guard await isTableAvailable(itemId: itemId, version: data.version) else { return false }
            guard makeCurrent else { return true }
            guard await setCurrent(itemId: itemId) else { return false }
            await persistCurrentTable(itemId: itemId)
            return true
        }

        let previousIdentities = await tableObjectIdentities()

        // Import into game memory first. Do not call generic updateGame here:
        // even its hidden/store path appends the root to gameModel.items and can
        // accidentally turn a cache-only package into the current presentation.
        // Persisting before the CRDT merge would also overwrite a player's
        // same-ID Table with the master's raw snapshot.
        do {
            try await importNetwork(from: encodedData)
        } catch {
            throw ItemGameStorableError.networkDecoding
        }

        let importedTables = await newlyImportedTables(comparedWith: previousIdentities)
        var importedVersions = await versions(of: importedTables)
        guard importedTables[itemId] != nil else { return false }

        // The envelope is the game master's authoritative package version.
        // Import repair may normalize legacy categories/tags, so recomputing
        // the root version after import is not guaranteed to reproduce the
        // pre-export value even though these are the canonical bytes. Keep the
        // transmitted baseline for the requested root; nested Tables can use
        // their imported, pre-player-merge versions.
        importedVersions[itemId] = data.version

        // Only the ids the import actually touched need a persisted copy for
        // the merge below — copying every Table in the library (regardless
        // of package size) previously scaled with library size instead of
        // package size. See CODE_AUDIT_Game §7.3.
        let persistentTables = await persistentTableCopies(for: Set(importedTables.keys))

        await mergeAndPersistImportedTables(importedTables, persistentTables: persistentTables, makeCurrent: makeCurrent)

        if makeCurrent, await !setCurrent(itemId: itemId) {
            return false
        }

        await markAvailable(importedVersions)
        return true
    }

    @MainActor
    private func persistentTableCopies(for ids: Set<UUID>) -> [UUID: TableModel] {
        ids.reduce(into: [:]) { result, id in
            guard let item = itemController.itemSync(for: id, noGame: true) else { return }
            result[id] = item.copy()
        }
    }

    @MainActor
    private func tableObjectIdentities() -> [UUID: ObjectIdentifier] {
        gameModel.itemData.reduce(into: [:]) { result, entry in
            guard let table = entry.value as? TableModel else { return }
            result[entry.key] = ObjectIdentifier(table)
        }
    }

    @MainActor
    private func newlyImportedTables(comparedWith previous: [UUID: ObjectIdentifier]) -> [UUID: TableModel] {
        gameModel.itemData.reduce(into: [:]) { result, entry in
            guard let table = entry.value as? TableModel,
                  previous[entry.key] != ObjectIdentifier(table)
            else { return }
            result[entry.key] = table
        }
    }

    @MainActor
    private func persistCurrentTable(itemId: UUID) {
        guard let table = gameModel.itemData[itemId] as? TableModel else { return }
        itemController.replaceForGame(model: table, isInsert: true, policy: .persist)
    }

    @MainActor
    private func versions(of tables: [UUID: TableModel]) -> [UUID: Int] {
        tables.mapValues(\.version)
    }

    @MainActor
    private func mergeAndPersistImportedTables(
        _ importedTables: [UUID: TableModel],
        persistentTables: [UUID: TableModel],
        makeCurrent: Bool
    ) {
        for (id, imported) in importedTables {
            let merged = persistentTables[id].map { imported.merge($0) } ?? imported
            gameModel.itemData[id] = merged
            if makeCurrent {
                itemController.replaceForGame(model: merged, isInsert: true, policy: .persist)
            }
        }
    }

    @MainActor
    private func markAvailable(_ importedVersions: [UUID: Int]) {
        for (id, version) in importedVersions {
            tableGameAvailabilityModel.markAvailable(itemId: id, version: version)
        }
    }
}
