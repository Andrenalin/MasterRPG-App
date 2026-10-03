// @copyright André Trettin

import CoreRPG
import Foundation

// MARK: - Network Sync
// Split out of GameController.swift's `ValueGameStorable` conformance —
// see CODE_AUDIT_Character §9.8.

extension GameController {
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
    public func updatePlayer(data: NetworkCodableDataType, policy: PeerImportPolicy?) async throws {
        guard data.type == itemControllable.config.module,
              let encodedData = data.data
        else { throw ItemGameStorableError.wrongData }
        try await importNetwork(from: encodedData, forceSave: true, peerPolicy: policy)
        // The live game copy is refreshed by the import itself: a `forceSave` write goes through
        // `ItemControllable.replace`, whose `syncGameMemoryIfLoaded` updates the loaded game copy
        // in place. The block below re-read that same game copy and replaced it with itself; it
        // now reads the library copy, so it only acts if the import ever stops doing that.
        // See CODE_AUDIT_Folder §5.30.
        //
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
        // `@Observable` instance must see the change through its own
        // reference. A full resync fires on every reconnect and on every
        // advertised-version mismatch, i.e. potentially after every single
        // edit in an active session, so swapping the reference here keeps
        // churning every view that tracks this character. Matches the
        // identity-preserving pattern already used by
        // `ItemControllable.replaceInGameMemory(model:)`'s "existing" branch
        // and `syncGameMemoryIfLoaded`.
        if let existing = gameModel.itemData[data.id] as? ValueModel,
           let refreshed = itemController.itemSync(for: data.id, noGame: true)?.copy() {
            _ = existing.replace(with: refreshed)
        }
    }
}
