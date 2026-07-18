// @copyright André Trettin

import CoreRPG
import DiceRPG
import Foundation

public protocol TableGameStorable {
    @MainActor func addResult(_ result: ResultCategory, value: String)
    func requestTableResult(for itemId: UUID, diceId: UUID, diceResult: String, networkActions: NetworkActions?, valueActions: ValueActions) async
    @MainActor func isTableAvailable(itemId: UUID, version: Int) -> Bool
    func receiveTable(itemId: UUID, data: NetworkCodableDataType, makeCurrent: Bool) async throws -> Bool
}

@MainActor
private final class TableGameAvailabilityModel: Sendable {
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

struct GameController: Sendable {
    @MainActor init(diceRoot: DiceRootModel, itemController: ItemController, exportController: ExportController) {
        self.diceRoot = diceRoot
        self.itemController = itemController
        self.exportController = exportController

        self.gameModel = ItemGameModel(itemDataModel: itemController.itemDataModel)
        self.tableGameAvailabilityModel = TableGameAvailabilityModel()
    }

    let diceRoot: DiceRootModel
    let itemController: ItemController
    let exportController: ExportController

    let gameModel: ItemGameModel
    private let tableGameAvailabilityModel: TableGameAvailabilityModel

    @MainActor func gameItem(for itemId: UUID) -> TableModel {
        (gameModel.itemData[itemId] as? TableModel) ?? itemController.itemOrEmpty(for: itemId)
    }
    
    @MainActor func setGame(item: ItemGameModel.ModelType, itemId: UUID) {
        if gameModel.items.firstIndex(where: { $0 == itemId }) != nil {
            gameModel.itemData[itemId] = item
        } else {
            gameModel.items.insert(itemId, at: 0)
            gameModel.itemData[itemId] = item
        }
    }
    
    @MainActor func currentItem() -> TableModel {
        gameItem(for: gameModel.currentItemId ?? UUID())
    }
}

extension GameController: GameControllable {
    var itemControllable: any ItemControllable { itemController as (any ItemControllable) }
    var exportControllable: any ExportControllable { exportController as ExportControllable }

    @MainActor
    func resetGameState() {
        tableGameAvailabilityModel.reset()
    }
}

extension GameController: TableGameStorable {
    @MainActor public func addResult(_ result: ResultCategory, value: String) {
        guard result.module == .table else { return }
        let model = gameItem(for: result.id)
        if let childId = result.childId {
             model[childId].diceResult = value
        } else {
            model.diceResult = value
        }
    }
    
    func requestTableResult(for itemId: UUID, diceId: UUID, diceResult: String, networkActions: NetworkActions?, valueActions: ValueActions) async {
        guard let networkActions else { return }
        _ = await setCurrent(itemId: itemId)
        let diceNum = await diceRoot.diceGameControllable.number(for: diceId, result: diceResult)
        guard let entryId = await entry(for: itemId, with: diceNum) else { return }

        // Model access is MainActor-isolated; extract the Sendable strings there.
        let (name, value) = await MainActor.run {
            let model = gameItem(for: itemId)
            return (model.name, "\(model[entryId].content) 🎲 \(diceResult)")
        }
        let result = valueActions.createEntryResult(name, value, ResultCategory(id: itemId, childId: entryId, module: itemController.config.module))
        await networkActions.game(result, .valueResult, nil)
    }

    @MainActor
    func entry(for id: UUID, with result: Int) -> UUID? {
        let item = gameItem(for: id)
        switch item.tableType {
        case .dice:
            if let _ = item.diceId {
                let entry = item.entries.first {
                    let numbers = $0.name.split(separator: "-").compactMap { Int($0) }
                    if let last = numbers.last {
                        return result <= last
                    }
                    return false
                }
                if let uuid = entry?.id {
                    return uuid
                }
            }
            return nil
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
        guard data.type == .table, data.id == itemId else {
            throw ItemGameStorableError.wrongData
        }

        guard data.version != 0 else { return false }

        guard let encodedData = data.data else {
            guard await isTableAvailable(itemId: itemId, version: data.version) else { return false }
            guard makeCurrent else { return true }
            guard await setCurrent(itemId: itemId) else { return false }
            await MainActor.run {
                guard let table = gameModel.itemData[itemId] as? TableModel else { return }
                itemController.replaceForGame(model: table, isInsert: true, policy: .persist)
            }
            return true
        }

        let persistentTables = await persistentTableCopies()
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
        var importedVersions = await MainActor.run {
            importedTables.mapValues(\.version)
        }
        guard importedTables[itemId] != nil else { return false }

        // The envelope is the game master's authoritative package version.
        // Import repair may normalize legacy categories/tags, so recomputing
        // the root version after import is not guaranteed to reproduce the
        // pre-export value even though these are the canonical bytes. Keep the
        // transmitted baseline for the requested root; nested Tables can use
        // their imported, pre-player-merge versions.
        importedVersions[itemId] = data.version

        await MainActor.run {
            for (id, imported) in importedTables {
                let merged = persistentTables[id].map { imported.merge($0) } ?? imported
                gameModel.itemData[id] = merged
                if makeCurrent {
                    itemController.replaceForGame(model: merged, isInsert: true, policy: .persist)
                }
            }
        }

        if makeCurrent, await !setCurrent(itemId: itemId) {
            return false
        }

        await MainActor.run {
            for (id, version) in importedVersions {
                tableGameAvailabilityModel.markAvailable(itemId: id, version: version)
            }
        }
        return true
    }

    @MainActor
    private func persistentTableCopies() -> [UUID: TableModel] {
        itemController.itemDataModel.items.reduce(into: [:]) { result, id in
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
}
