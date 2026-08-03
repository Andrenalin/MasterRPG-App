// @copyright André Trettin

import CoreRPG
import DiceRPG
import Foundation
import os.log
import PhotoRPG
import TableRPG

@MainActor @Observable
final class ValueGameModel: Sendable {
    init() {}

    var gameEntryDiceId: [UUID: UUID] = [:]
    var gameDiceId: [UUID: UUID] = [:]
    
    func resetGameDiceId(itemId: UUID, entryId: UUID) {
        gameEntryDiceId[entryId] = nil
    }
}

/// A resolved route from a top-level Character down to one of its entries,
/// through zero or more nested value "group" tables (`ValueModel.groupId`).
/// `duplicateWithoutCopy()` only mints fresh ids for a Character's own
/// top-level entries — nested group tables are shared, not duplicated — so
/// this path lets `gameEntry(matching:characterId:)` relocate the
/// structurally-equivalent entry on a different (e.g. battle-copy) Character
/// without relying on the id, which may not carry over.
public struct GameEntryPath: Sendable {
    /// Root-to-leaf entry indices: `indices[0]` is the index of the
    /// top-level entry (possibly a group link) on the root Character;
    /// each subsequent index is within the group the previous entry links to.
    public let indices: [Int]
    public let rootCharacterId: UUID
    public let name: String
}

public protocol ValueGameStorable {
    @MainActor func focusDice(for itemId: UUID) -> UUID?
    @MainActor func imageIds(for id: UUID) -> [UUID]
    @MainActor func playerPinPhoto(for characterId: UUID) -> UUID?
    /// Creates an independent, memory-only Character instance for one battle
    /// combatant. Reusing a monster template therefore never aliases the values
    /// of another monster placed from the same template.
    @MainActor func createBattleCharacterCopy(for characterId: UUID) -> UUID?
    @MainActor func battleCharacterCopy(for gameCharacterId: UUID) -> ValueModel?
    /// Searches `characterId`'s entries — including nested value "group"
    /// tables (`ValueModel.valueId`) — for one whose name matches any of
    /// `names`, falling back to an entry whose content contains an embedded
    /// link display-named after any of `names` (e.g. an entry named
    /// "current" that links to a "HitPoints" reference).
    @MainActor func gameEntry(
        matchingAny names: [String],
        characterId: UUID
    ) -> ValueEntryModel?
    @MainActor func gameEntry(
        characterId: UUID,
        entryId: UUID
    ) -> ValueEntryModel?
    /// Walks `entryId`'s containing item up through its `groupId` chain to
    /// the owning root Character, recording the entry index needed at each
    /// level. `itemId` is whichever item directly contains `entryId` — the
    /// root Character itself if the entry isn't nested in a group.
    @MainActor func gameEntryPath(itemId: UUID, entryId: UUID) -> GameEntryPath?
    /// Replays a `GameEntryPath` against `characterId`, bounds-checking each
    /// index while descending, then verifying the resolved entry's name
    /// matches as a final guard against structural drift between the two
    /// Characters.
    @MainActor func gameEntry(matching path: GameEntryPath, characterId: UUID) -> ValueEntryModel?
    @MainActor func gameEntryDisplayValue(
        characterId: UUID,
        entryId: UUID
    ) -> String?
    /// Updates an existing game-memory entry while preserving its links.
    @MainActor @discardableResult func applyGameValueEntryUpdate(
        _ update: GameValueEntryUpdate
    ) -> Bool
    /// Removes battle-only runtime Characters after their non-player
    /// combatants leave the encounter. Persistent templates are never touched.
    @MainActor func removeBattleCharacterCopies(_ gameCharacterIds: Set<UUID>)
    @MainActor func startGame(for id: UUID?) async
    func updatePlayer(data: NetworkCodableDataType) async throws
}

struct GameController: Sendable {
    @MainActor init(root: CharacterRootModel, diceRoot: DiceRootModel, photoRoot: PhotoRootModel, tableRoot: TableRootModel, itemController: ItemController, exportController: ExportController) {
        self.root = root
        self.diceRoot = diceRoot
        self.photoRoot = photoRoot
        self.tableRoot = tableRoot
        
        self.itemController = itemController
        self.exportController = exportController

        self.gameModel = ItemGameModel(itemDataModel: itemController.itemDataModel)
        self.gameDiceModel = ValueGameModel()
    }
    
    let root: CharacterRootModel
    let diceRoot: DiceRootModel
    let photoRoot: PhotoRootModel
    let tableRoot: TableRootModel
    
    let itemController: ItemController
    let exportController: ExportController

    let gameModel: ItemGameModel
    let gameDiceModel: ValueGameModel
    
    @MainActor func gameItem(for itemId: UUID) -> ValueModel {
        (gameModel.itemData[itemId] as? ValueModel) ?? itemController.itemOrEmpty(for: itemId)
    }
    
    @MainActor func setGame(item: ItemGameModel.ModelType, itemId: UUID) {
        if gameModel.items.firstIndex(where: { $0 == itemId }) != nil {
            gameModel.itemData[itemId] = item
        } else {
            gameModel.items.insert(itemId, at: 0)
            gameModel.itemData[itemId] = item
        }
    }
    
    @MainActor func currentItem() -> ValueModel {
        gameItem(for: gameModel.currentItemId ?? UUID())
    }
}

// MARK: - Dice for the game

extension GameController {
    @MainActor
    func gameDiceId(itemId: UUID, entryId: UUID) -> UUID? {
        let entry = gameItem(for: itemId)[entryId]
        guard let diceId = entry.diceId else { return nil }
        guard entry.type == .number else { return diceId }
        let gameEntryDiceId = gameDiceModel.gameEntryDiceId[entryId]
        let gameDiceId: UUID?
        if gameEntryDiceId != diceId {
            // reset
            gameDiceModel.gameEntryDiceId[entryId] = diceId
            gameDiceId = nil
        } else {
            gameDiceId = gameDiceModel.gameDiceId[entryId]
        }
        let newDiceId = diceRoot.diceGameControllable.createGameDice(for: diceId, gameDiceId: gameDiceId)
        if gameDiceId != nil {
            return gameDiceId
        }
        gameDiceModel.gameDiceId[entryId] = newDiceId
        return newDiceId
    }

    
    @MainActor
    func gameDiceId(itemId: UUID, diceId: UUID) -> UUID? {
        let gameEntryDiceId = gameDiceModel.gameEntryDiceId[itemId]
        let gameDiceId: UUID?
        if gameEntryDiceId != diceId {
            // reset
            gameDiceModel.gameEntryDiceId[itemId] = diceId
            gameDiceId = nil
        } else {
            gameDiceId = gameDiceModel.gameDiceId[itemId]
        }
        let newDiceId = diceRoot.diceGameControllable.createGameDice(for: diceId, gameDiceId: gameDiceId)
        if gameDiceId != nil {
            return gameDiceId
        }
        gameDiceModel.gameDiceId[itemId] = newDiceId
        return newDiceId
    }
    
    @MainActor
    func resetGameDiceId(itemId: UUID, entryId: UUID) {
        gameDiceModel.resetGameDiceId(itemId: itemId, entryId: entryId)
    }
}

extension GameController: GameControllable {
    var itemControllable: any ItemControllable { itemController as (any ItemControllable) }
    var exportControllable: any ExportControllable { exportController as ExportControllable }
}

extension GameController: ValueGameStorable {
    @MainActor
    public func focusDice(for itemId: UUID) -> UUID? {
        if let diceId = gameItem(for: itemId).diceId {
            return gameDiceId(itemId: itemId, diceId: diceId)
        }        
        guard let entry = gameItem(for: itemId).entries.first(where: { $0.diceId != nil }) else { return nil }
        return gameDiceId(itemId: itemId, entryId: entry.id)
    }

    @MainActor
    public func imageIds(for id: UUID) -> [UUID] {
        gameItem(for: id).photos
    }

    @MainActor
    public func playerPinPhoto(for characterId: UUID) -> UUID? {
        guard let itemId = root.linkController.validate(id: characterId, isCharacter: true) else { return nil }
        return itemController.itemOrEmpty(for: itemId).photoId
    }

    @MainActor
    public func createBattleCharacterCopy(for characterId: UUID) -> UUID? {
        guard let source = itemController.itemSync(for: characterId) else { return nil }
        let copy = source.duplicateWithoutCopy()
        // Battle clones are lookup-only runtime data. Do not add them to the
        // presented game item order: that would make the latest monster the
        // current Character whenever an encounter starts.
        gameModel.itemData[copy.id] = copy
        return copy.id
    }

    @MainActor
    public func battleCharacterCopy(for gameCharacterId: UUID) -> ValueModel? {
        gameModel.itemData[gameCharacterId] as? ValueModel
    }

    @MainActor
    public func gameEntry(
        matchingAny names: [String],
        characterId: UUID
    ) -> ValueEntryModel? {
        gameEntry(matchingAny: names, characterId: characterId, depth: 0)
    }

    @MainActor
    private func gameEntry(
        matchingAny names: [String],
        characterId: UUID,
        depth: Int
    ) -> ValueEntryModel? {
        guard depth < 10 else { return nil }
        let normalizedNames = names
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !normalizedNames.isEmpty else { return nil }

        let item = gameItem(for: characterId)
        if let direct = item.entries.first(where: { entry in
            let entryName = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return normalizedNames.contains {
                entryName.localizedCaseInsensitiveCompare($0) == .orderedSame
            }
        }) {
            return direct
        }
        if let linked = item.entries.first(where: { entry in
            entry.links(for: entry.value).contains { link in
                let linkName = link.name.trimmingCharacters(in: .whitespacesAndNewlines)
                return normalizedNames.contains {
                    linkName.localizedCaseInsensitiveCompare($0) == .orderedSame
                }
            }
        }) {
            return linked
        }
        for entry in item.entries {
            guard let valueId = entry.valueId,
                  let found = gameEntry(matchingAny: names, characterId: valueId, depth: depth + 1) else {
                continue
            }
            return found
        }
        return nil
    }

    /// Searches `characterId`'s own entries first, then descends into any
    /// nested value "group" tables (linked via `valueId`) — HP and other
    /// tracked values are frequently grouped, not top-level.
    @MainActor
    public func gameEntry(
        characterId: UUID,
        entryId: UUID
    ) -> ValueEntryModel? {
        gameEntry(characterId: characterId, entryId: entryId, depth: 0)
    }

    @MainActor
    private func gameEntry(characterId: UUID, entryId: UUID, depth: Int) -> ValueEntryModel? {
        guard depth < 10 else { return nil }
        let item = gameItem(for: characterId)
        if let direct = item.entries.first(where: { $0.id == entryId }) {
            return direct
        }
        for entry in item.entries {
            guard let valueId = entry.valueId,
                  let found = gameEntry(characterId: valueId, entryId: entryId, depth: depth + 1) else {
                continue
            }
            return found
        }
        return nil
    }

    @MainActor
    public func gameEntryPath(itemId: UUID, entryId: UUID) -> GameEntryPath? {
        var currentItem = gameItem(for: itemId)
        var currentItemId = itemId
        guard let leafIndex = currentItem.entries.firstIndex(where: { $0.id == entryId }) else {
            return nil
        }
        let name = currentItem.entries[leafIndex].name
        var indices = [leafIndex]

        while let ownerId = currentItem.groupId {
            let owner = gameItem(for: ownerId)
            guard let linkIndex = owner.entries.firstIndex(where: { $0.valueId == currentItemId }) else {
                return nil
            }
            indices.append(linkIndex)
            currentItem = owner
            currentItemId = ownerId
        }

        return GameEntryPath(indices: Array(indices.reversed()), rootCharacterId: currentItemId, name: name)
    }

    @MainActor
    public func gameEntry(matching path: GameEntryPath, characterId: UUID) -> ValueEntryModel? {
        guard !path.indices.isEmpty else { return nil }
        var currentItem = gameItem(for: characterId)
        var candidate: ValueEntryModel?
        for (offset, index) in path.indices.enumerated() {
            guard currentItem.entries.indices.contains(index) else { return nil }
            let entry = currentItem.entries[index]
            candidate = entry
            if offset < path.indices.count - 1 {
                guard let valueId = entry.valueId else { return nil }
                currentItem = gameItem(for: valueId)
            }
        }
        guard let candidate,
              candidate.name.trimmingCharacters(in: .whitespacesAndNewlines)
                  .localizedCaseInsensitiveCompare(
                      path.name.trimmingCharacters(in: .whitespacesAndNewlines)
                  ) == .orderedSame else {
            return nil
        }
        return candidate
    }

    @MainActor
    public func gameEntryDisplayValue(
        characterId: UUID,
        entryId: UUID
    ) -> String? {
        guard let entry = gameEntry(characterId: characterId, entryId: entryId) else {
            return nil
        }
        return root.linkController.calculate(entry: entry) ?? entry.value
    }

    @MainActor
    @discardableResult
    public func applyGameValueEntryUpdate(
        _ update: GameValueEntryUpdate
    ) -> Bool {
        guard let type = ValueEntryModel.ValueType(rawValue: update.typeRawValue) else {
            return false
        }
        let character: ValueModel
        if let current = gameModel.itemData[update.characterId] as? ValueModel {
            character = current
        } else if let stored = itemController.itemSync(for: update.characterId)?.copy() {
            // A player's Character is normally imported into the master's item
            // store during join. Promote a copy into game memory on the first
            // live value update so gameplay changes never mutate persistence.
            character = stored
            gameModel.itemData[update.characterId] = stored
        } else {
            return false
        }
        guard
              let index = character.entries.firstIndex(where: { $0.id == update.entryId }) else {
            return false
        }
        var entry = character.entries[index]
        let previous = entry
        entry.name = update.name
        entry.type = type
        entry.isGenerator = update.isGenerator
        entry.value = update.value
        entry.displayState = update.displayState
        if entry != previous {
            // diceId and valueId intentionally remain those of the master's
            // existing runtime entry.
            character.entries[index] = entry
        }
        return true
    }

    @MainActor
    public func removeBattleCharacterCopies(_ gameCharacterIds: Set<UUID>) {
        guard !gameCharacterIds.isEmpty else { return }
        let entryIds = gameCharacterIds.reduce(into: Set<UUID>()) { result, characterId in
            guard let character = gameModel.itemData[characterId] as? ValueModel else { return }
            result.formUnion(character.entries.map(\.id))
        }
        gameModel.items.removeAll { gameCharacterIds.contains($0) }
        for characterId in gameCharacterIds {
            gameModel.itemData[characterId] = nil
            gameDiceModel.gameEntryDiceId[characterId] = nil
            gameDiceModel.gameDiceId[characterId] = nil
        }
        for entryId in entryIds {
            gameDiceModel.gameEntryDiceId[entryId] = nil
            gameDiceModel.gameDiceId[entryId] = nil
        }
    }

    @MainActor
    public func startGame(for id: UUID?) async {
        guard let characterId = root.linkController.validate(id: id) else { return }
        await focus(on: [characterId])
    }

    public func updatePlayer(data: NetworkCodableDataType) async throws {
        guard data.type == itemControllable.config.module,
              let encodedData = data.data
        else { throw ItemGameStorableError.wrongData }
        try await importNetwork(from: encodedData, forceSave: true)
    }
}
