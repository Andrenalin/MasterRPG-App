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
    /// The deep-copied value groups of each battle clone (clone id to group copy ids), so the
    /// clone's HP/initiative groups are its own and go away with it. See CODE_AUDIT_23 §5.3.
    var battleGroupCopyIds: [UUID: Set<UUID>] = [:]

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
/// top-level entries and `createBattleCharacterCopy` gives each clone its own
/// group tables with fresh ids, so this path lets `gameEntry(matching:characterId:)` relocate the
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
    /// The game dice attached to an entry, the very instance the character sheet's row rolls, or
    /// `nil` when the entry has none. `itemId` is the item that directly contains the entry.
    @MainActor func gameDiceId(itemId: UUID, entryId: UUID) -> UUID?
    /// The calculated number the entry's dice compare against. Reading it in a view's `body`
    /// makes Observation track every entry its formula links to.
    @MainActor func diceCompareValue(itemId: UUID, entryId: UUID) -> Int?
    /// Resolves an arbitrary value string through the same link-substitution
    /// + arithmetic pipeline `gameEntryDisplayValue` runs a stored entry's own
    /// `value` through — for evaluating just a *portion* of another entry's
    /// value, such as `MapRPG`'s hit-points "base|modifier" convention, where
    /// "base" may itself be a markdown link (e.g. `[Lebenskraft](RPG://...)`)
    /// rather than a literal number, and possibly several link hops deep.
    @MainActor func calculatedValue(_ text: String, type: ValueEntryModel.ValueType) -> String?
    /// The entry's current value as a whole number, with links and the
    /// "base|modifier" convention resolved, or `nil` when it isn't numeric.
    @MainActor func gameEntryCurrentNumber(characterId: UUID, entryId: UUID) -> Int?
    /// An entry value as its maximum ("base", the text before the modifier
    /// separator) and its current amount (base plus modifier), with value
    /// links resolved on both sides. `nil` when the base is not a number —
    /// e.g. free text, or a formula that does not evaluate. The Character
    /// module owns the "base|modifier" convention; callers such as the battle
    /// health ring use this instead of parsing the raw text themselves.
    @MainActor func gameValueBaseAndCurrent(_ value: String) -> (base: Double, current: Double)?
    /// Makes `number` the entry's current value in game memory. The base
    /// (and any link in it) is kept; the difference is written as the
    /// "|modifier". Returns `false` when nothing changed or the stored text
    /// has no numeric base to adjust.
    @MainActor @discardableResult func setGameEntryCurrentNumber(
        _ number: Int,
        characterId: UUID,
        entryId: UUID
    ) -> Bool
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
        // Nested value groups hold the clone's HP and initiative; sharing the template's group
        // items would make damage to one clone hit every clone and the template.
        var groupCopies: [UUID: UUID] = [:]
        copyValueGroups(into: copy, groupCopies: &groupCopies, depth: 0)
        if !groupCopies.isEmpty {
            gameDiceModel.battleGroupCopyIds[copy.id] = Set(groupCopies.values)
        }
        // Battle clones are lookup-only runtime data. Do not add them to the
        // presented game item order: that would make the latest monster the
        // current Character whenever an encounter starts.
        gameModel.itemData[copy.id] = copy
        return copy.id
    }

    /// Replaces each group entry's `valueId` in `owner` with a fresh copy of the group item,
    /// recursively. One group referenced twice (or in a cycle) maps to one copy.
    @MainActor
    private func copyValueGroups(into owner: ValueModel, groupCopies: inout [UUID: UUID], depth: Int) {
        guard depth < RecursionLimits.maxValueLinkDepth else { return }
        for index in owner.entries.indices {
            guard let groupId = owner.entries[index].valueId else { continue }
            if let existing = groupCopies[groupId] {
                owner.entries[index].valueId = existing
                continue
            }
            guard let group = itemController.itemSync(for: groupId) else { continue }
            let groupCopy = group.duplicateWithoutCopy()
            groupCopy.groupId = owner.id
            groupCopies[groupId] = groupCopy.id
            gameModel.itemData[groupCopy.id] = groupCopy
            owner.entries[index].valueId = groupCopy.id
            copyValueGroups(into: groupCopy, groupCopies: &groupCopies, depth: depth + 1)
        }
    }

    @MainActor
    public func battleCharacterCopy(for gameCharacterId: UUID) -> ValueModel? {
        gameModel.itemData[gameCharacterId] as? ValueModel
    }

    @MainActor
    public func removeBattleCharacterCopies(_ gameCharacterIds: Set<UUID>) {
        guard !gameCharacterIds.isEmpty else { return }
        var itemIds = gameCharacterIds
        for characterId in gameCharacterIds {
            itemIds.formUnion(gameDiceModel.battleGroupCopyIds.removeValue(forKey: characterId) ?? [])
        }
        let entryIds = itemIds.reduce(into: Set<UUID>()) { result, itemId in
            guard let item = gameModel.itemData[itemId] as? ValueModel else { return }
            result.formUnion(item.entries.map(\.id))
        }
        gameModel.items.removeAll { gameCharacterIds.contains($0) }
        for characterId in itemIds {
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
