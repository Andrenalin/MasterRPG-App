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
    func updatePlayer(data: NetworkCodableDataType) async throws
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

// MARK: - Dice for the game

extension GameController {
    @MainActor
    func gameDiceId(itemId: UUID, entryId: UUID) -> UUID? {
        let entry = gameItem(for: itemId)[entryId]
        guard let diceId = entry.diceId else { return nil }
        guard entry.type == .number else { return diceId }
        return cachedGameDice(key: entryId, diceId: diceId)
    }

    @MainActor
    func gameDiceId(itemId: UUID, diceId: UUID) -> UUID? {
        cachedGameDice(key: itemId, diceId: diceId)
    }

    /// Shared body for both `gameDiceId` overloads: returns the cached game
    /// dice for `key` (an entry id or item id, per caller), invalidating the
    /// cache when the underlying dice template changed. See CODE_AUDIT_Game §9.23.
    @MainActor
    private func cachedGameDice(key: UUID, diceId: UUID) -> UUID? {
        let gameEntryDiceId = gameDiceModel.gameEntryDiceId[key]
        let gameDiceId: UUID?
        if gameEntryDiceId != diceId {
            // reset
            gameDiceModel.gameEntryDiceId[key] = diceId
            gameDiceId = nil
        } else {
            gameDiceId = gameDiceModel.gameDiceId[key]
        }
        let newDiceId = diceRoot.diceGameControllable.createGameDice(for: diceId, gameDiceId: gameDiceId)
        if gameDiceId != nil {
            return gameDiceId
        }
        gameDiceModel.gameDiceId[key] = newDiceId
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
        guard depth < RecursionLimits.maxValueLinkDepth else { return nil }
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
        guard depth < RecursionLimits.maxValueLinkDepth else { return nil }
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

        // `groupId` comes from Character data that can arrive over the
        // network (updatePlayer(data:) → importNetwork); a crafted cyclic
        // pair must not hang this loop forever. See CODE_AUDIT_Game §5.7.
        var depth = 0
        while let ownerId = currentItem.groupId {
            guard depth < RecursionLimits.maxValueLinkDepth else { return nil }
            let owner = gameItem(for: ownerId)
            guard let linkIndex = owner.entries.firstIndex(where: { $0.valueId == currentItemId }) else {
                return nil
            }
            indices.append(linkIndex)
            currentItem = owner
            currentItemId = ownerId
            depth += 1
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
    public func calculatedValue(_ text: String, type: ValueEntryModel.ValueType) -> String? {
        // A synthetic, unstored entry: `LinkController.calculate(entry:)` only
        // needs `type` (for `canCalculate`) and `value` (to scan for links and
        // evaluate) — it doesn't require the entry to actually exist anywhere.
        let entry = ValueEntryModel(id: UUID(), name: "", type: type, value: text)
        return root.linkController.calculate(entry: entry) ?? text
    }

    /// Game-memory copy of `itemId`, promoting one from persistence on first
    /// touch — the shared half of `applyGameValueEntryUpdate`'s two
    /// resolution paths. A player's Character is normally imported into the
    /// master's item store during join; this is what makes the *first* live
    /// value update (whichever item it targets) promote a copy into game
    /// memory so gameplay changes never mutate persistence.
    @MainActor
    private func gameMemoryCopy(for itemId: UUID) -> ValueModel? {
        if let current = gameModel.itemData[itemId] as? ValueModel {
            return current
        }
        guard let stored = itemController.itemSync(for: itemId)?.copy() else { return nil }
        gameModel.itemData[itemId] = stored
        return stored
    }

    /// Walks `path` (root-to-leaf indices, from `GameEntryPath.indices`) to
    /// the `ValueModel` that actually owns the leaf entry, together with its
    /// index in that model's own `entries` — the mutation must land on
    /// whichever nested group actually owns the entry, not necessarily
    /// `rootCharacterId`'s own top-level entries. See CODE_AUDIT_Game §5.3.
    @MainActor
    private func resolveGroupedEntry(
        rootCharacterId: UUID,
        path: [Int]
    ) -> (owner: ValueModel, index: Int)? {
        guard !path.isEmpty, var currentItem = gameMemoryCopy(for: rootCharacterId) else { return nil }
        for (offset, index) in path.enumerated() {
            guard currentItem.entries.indices.contains(index) else { return nil }
            if offset == path.count - 1 {
                return (currentItem, index)
            }
            guard let valueId = currentItem.entries[index].valueId,
                  let nested = gameMemoryCopy(for: valueId) else { return nil }
            currentItem = nested
        }
        return nil
    }

    @MainActor
    @discardableResult
    public func applyGameValueEntryUpdate(
        _ update: GameValueEntryUpdate
    ) -> Bool {
        guard let type = ValueEntryModel.ValueType(rawValue: update.typeRawValue) else {
            return false
        }
        let owner: ValueModel
        let index: Int
        // Most tracked values (HP included) are frequently grouped, not
        // top-level — resolve through the same path a battle copy uses
        // instead of only ever checking characterId's own top-level entries.
        // See CODE_AUDIT_Game §5.3.
        if let path = update.path, !path.isEmpty {
            guard let resolved = resolveGroupedEntry(rootCharacterId: update.characterId, path: path) else {
                return false
            }
            (owner, index) = resolved
        } else {
            guard let character = gameMemoryCopy(for: update.characterId),
                  let topLevelIndex = character.entries.firstIndex(where: { $0.id == update.entryId }) else {
                return false
            }
            owner = character
            index = topLevelIndex
        }
        var entry = owner.entries[index]
        let previous = entry
        entry.name = update.name
        entry.type = type
        entry.isGenerator = update.isGenerator
        entry.value = update.value
        entry.displayState = update.displayState
        if entry != previous {
            // diceId and valueId intentionally remain those of the master's
            // existing runtime entry.
            owner.entries[index] = entry
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

    @MainActor
    public func updatePlayer(data: NetworkCodableDataType) async throws {
        guard data.type == itemControllable.config.module,
              let encodedData = data.data
        else { throw ItemGameStorableError.wrongData }
        try await importNetwork(from: encodedData, forceSave: true)
        // A full-package resync (sent on reconnect, or whenever the master's
        // cached version differs from what the player advertises) only merges
        // into the persisted library above — `gameItem(for:)`, and everything
        // built on it (`healthPercent(for:)` included), prefers a live
        // `gameModel.itemData` copy once one exists. That copy gets promoted
        // the first time any live per-field edit arrives (see
        // `applyGameValueEntryUpdate`'s own comment), so without this a
        // later full resync silently stops reaching gameplay reads — the
        // player's own edits keep landing, this just leaves the *next*
        // full-package sync (reconnect, etc.) unable to override them.
        //
        // Mutate the existing live instance in place (`replace(with:)`)
        // rather than swapping in a fresh `.copy()` under the same dictionary
        // key: any view or model already holding a reference to this exact
        // `@Observable` instance — e.g. `LinkController.updateValueCalculation`'s
        // manually-armed `withObservationTracking`, which `EntryListDiceRow`
        // relies on to notice a linked value changed — must see the change
        // through its own reference. A full resync fires on every reconnect
        // and on every advertised-version mismatch, i.e. potentially after
        // every single edit in an active session, so replacing the reference
        // here silently orphaned that tracking mid-session: the inline dice
        // display stopped picking up further calculated-value changes even
        // though the underlying data kept updating correctly. Matches the
        // identity-preserving pattern already used by
        // `ItemControllable.replaceInGameMemory(model:)`'s "existing" branch
        // and `syncGameMemoryIfLoaded`.
        if let existing = gameModel.itemData[data.id] as? ValueModel,
           let refreshed = itemController.itemSync(for: data.id)?.copy() {
            _ = existing.replace(with: refreshed)
        }
    }

    @MainActor
    public func addItem(sheet: SheetModel, characterId: UUID, forceSave: Bool) async -> UUID? {
        guard let newValueId = await root.editController.addItem(sheet: sheet, forceSave: forceSave) else { return nil }
        let entryId = await root.editController.addItemAsGroup(itemId: characterId, groupId: newValueId, forceSave: forceSave)
        root.editController.editorModel.gameSheetRootModel?.updateFromRoot()
        return entryId
    }
}
