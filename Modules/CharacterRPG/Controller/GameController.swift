// @copyright André Trettin

import CoreRPG
import DiceRPG
import Foundation
import os.log
import PhotoRPG
import TableRPG

@MainActor @Observable
final class ValueGameModel {
    init() {}

    var gameEntryDiceId: [UUID: UUID] = [:]
    var gameDiceId: [UUID: UUID] = [:]

    /// Clears both dice-cache dictionaries for `entryId`, matching the
    /// symmetric clearing `removeBattleCharacterCopies` already does for
    /// every entry it tears down — previously only `gameEntryDiceId` was
    /// cleared here, leaving a stale `gameDiceId` entry behind.
    /// See CODE_AUDIT_Character §9.6.
    func resetGameDiceId(entryId: UUID) {
        gameEntryDiceId[entryId] = nil
        gameDiceId[entryId] = nil
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

public protocol ValueGameStorable: Sendable {
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
    /// Resolves an arbitrary value string through the same link-substitution
    /// + arithmetic pipeline `gameEntryDisplayValue` runs a stored entry's own
    /// `value` through — for evaluating just a *portion* of another entry's
    /// value, such as `MapRPG`'s hit-points "base|modifier" convention, where
    /// "base" may itself be a markdown link (e.g. `[Lebenskraft](RPG://...)`)
    /// rather than a literal number, and possibly several link hops deep.
    @MainActor func calculatedValue(_ text: String, type: ValueEntryModel.ValueType) -> String?
    /// Updates an existing game-memory entry while preserving its links.
    @MainActor @discardableResult func applyGameValueEntryUpdate(
        _ update: GameValueEntryUpdate
    ) -> Bool
    /// Removes battle-only runtime Characters after their non-player
    /// combatants leave the encounter. Persistent templates are never touched.
    @MainActor func removeBattleCharacterCopies(_ gameCharacterIds: Set<UUID>)
    @MainActor func startGame(for id: UUID?) async
    /// Imports a Character package a player sent. `policy` restricts which items of the
    /// package may be written (see `PeerImportPolicy`); `nil` imports everything.
    @MainActor func updatePlayer(data: NetworkCodableDataType, policy: PeerImportPolicy?) async throws
    /// Creates a new Character value from a sheet built elsewhere (e.g. a
    /// Table-generated outcome pushed by the master over the active game
    /// session — see `PlayerController+Value.handleAddItem(_:)`) and nests
    /// it as a group entry directly under `characterId`, rather than
    /// leaving it a disconnected top-level value the way the local Save
    /// button's `EditControllable.addItem(sheet:forceSave:)` does.
    /// `forceSave` bypasses the in-game-memory-only save path (see
    /// `ItemControllable.replace(model:isInsert:forceSave:)`). Returns the
    /// new value's id, or `nil` if `characterId` doesn't resolve to a real
    /// Character or nothing was created.
    @MainActor func addItem(sheet: SheetModel, characterId: UUID, forceSave: Bool) async -> UUID?
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
    
}

// gameItem(for:)/setGame(item:itemId:)/currentItem() come from
// ModuleGameControllable's default implementations. See CODE_AUDIT_Game §9.1.
extension GameController: ModuleGameControllable {}

extension GameController: GameControllable {
    var itemControllable: any ItemControllable { itemController as (any ItemControllable) }
    var exportControllable: any ExportControllable { exportController as ExportControllable }

    /// Clears the live game view's persistent sheet slot when the game ends,
    /// so a later, unrelated presentation never reuses a stale instance.
    /// See `CharacterRootModel.startGameSheetRootModel()` for construction.
    @MainActor func resetGameState() {
        root.editController.editorModel.gameSheetRootModel = nil
    }
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
        guard let itemId = root.linkController.validate(id: characterId) else { return nil }
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
        root.startGameSheetRootModel(itemId: characterId)
    }

    @MainActor
    public func addItem(sheet: SheetModel, characterId: UUID, forceSave: Bool) async -> UUID? {
        guard let newValueId = await root.editController.addItem(sheet: sheet, forceSave: forceSave) else { return nil }
        let entryId = await root.editController.addItemAsGroup(itemId: characterId, groupId: newValueId, forceSave: forceSave)
        root.editController.editorModel.gameSheetRootModel?.updateFromRoot()
        return entryId
    }
}

public extension ValueGameStorable {
    /// Unrestricted import, for callers that trust the package (own device, tests).
    @MainActor func updatePlayer(data: NetworkCodableDataType) async throws {
        try await updatePlayer(data: data, policy: nil)
    }
}
