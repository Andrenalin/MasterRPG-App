// @copyright André Trettin

import CoreRPG
import DiceRPG
import Foundation

// MARK: - Dice for the game
// Split out of GameController.swift — see CODE_AUDIT_Character §9.8.

extension GameController {
    /// The game dice of an entry, read only: safe to call from a view `body`. `nil` until
    /// `ensureGameDice(itemId:entryId:)` created it for the entry's current dice template.
    /// See CODE_AUDIT_26 §8.2.
    @MainActor
    func gameDiceId(itemId: UUID, entryId: UUID) -> UUID? {
        let entry = gameItem(for: itemId)[entryId]
        guard let diceId = entry.diceId, entry.supportsDice else { return nil }
        guard gameDiceModel.gameEntryDiceId[entryId] == diceId else { return nil }
        return gameDiceModel.gameDiceId[entryId]
    }

    @MainActor
    func templateDiceId(itemId: UUID, entryId: UUID) -> UUID? {
        gameItem(for: itemId)[entryId].diceId
    }

    /// Creates the entry's game dice if it has none for the current dice template and returns it.
    /// Mutates observable state, so it is called from a task or a controller, not from `body`.
    @MainActor
    @discardableResult
    func ensureGameDice(itemId: UUID, entryId: UUID) -> UUID? {
        let entry = gameItem(for: itemId)[entryId]
        guard let diceId = entry.diceId, entry.supportsDice else { return nil }
        return cachedGameDice(key: entryId, diceId: diceId)
    }

    @MainActor
    func diceCompareValue(itemId: UUID, entryId: UUID) -> Int? {
        root.linkController.diceCompareValue(itemId: itemId, entryId: entryId)
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
            // The template changed: the game dice made from the old one is removed instead of
            // staying in the game store for good. See CODE_AUDIT_26 §8.2.
            if let superseded = gameDiceModel.gameDiceId[key] {
                diceRoot.diceGameControllable.removeGameDice(superseded)
                gameDiceModel.gameDiceId[key] = nil
            }
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
    func resetGameDiceId(entryId: UUID) {
        gameDiceModel.resetGameDiceId(entryId: entryId)
    }
}
