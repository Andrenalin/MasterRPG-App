// @copyright André Trettin

import CoreRPG
import DiceRPG
import Foundation

public protocol TableGameStorable: Sendable {
    /// `senderId` is the player who rolled; a roll handed to one player only counts from them.
    @MainActor func addResult(
        _ result: ResultCategory,
        diceResult: DiceResultModel,
        senderId: UUID?
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
        // The operation itself is chained: a gate that only awaited the previous gate finished
        // at once, so a second call ran while the first was still suspended.
        // See CODE_AUDIT_21 §5.22.
        let task = Task { () async throws -> T in
            await previous?.value
            return try await operation()
        }
        tails[itemId] = (token, Task { _ = await task.result })
        defer {
            if tails[itemId]?.token == token {
                tails[itemId] = nil
            }
        }
        return try await task.value
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
        diceResult: DiceResultModel,
        senderId: UUID?
    ) {
        guard result.module == .table else { return }
        if generationSessionStore.consume(
            category: result,
            diceResult: diceResult,
            senderId: senderId
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

        // Import into game memory first. Do not call generic updateGame here:
        // even its hidden/store path appends the root to gameModel.items and can
        // accidentally turn a cache-only package into the current presentation.
        // Persisting before the CRDT merge would also overwrite a player's
        // same-ID Table with the master's raw snapshot.
        let appliedIds: Set<UUID>
        do {
            appliedIds = try await importNetwork(from: encodedData)[.table] ?? []
        } catch {
            throw ItemGameStorableError.networkDecoding
        }

        // The ids the import wrote, not a change of object identity: a table already in game
        // memory is updated in place, so a second delivery of an edited table looked like
        // nothing was imported. See CODE_AUDIT_Folder §5.10.
        let importedTables = await gameTables(for: appliedIds)
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
    private func gameTables(for ids: Set<UUID>) -> [UUID: TableModel] {
        ids.reduce(into: [:]) { result, id in
            if let table = gameModel.itemData[id] as? TableModel {
                result[id] = table
            }
        }
    }

    @MainActor
    private func persistCurrentTable(itemId: UUID) {
        guard let table = gameModel.itemData[itemId] as? TableModel else { return }
        // Merged with the player's library copy, keeping its folder. See CODE_AUDIT_Folder §5.23.
        itemController.persistFromGame(model: table, authoritative: false)
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
