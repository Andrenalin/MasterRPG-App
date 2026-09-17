// @copyright André Trettin

import CoreRPG
import DiceRPG
import Foundation

// MARK: - Dice for the game
// Split out of GameController.swift — see CODE_AUDIT_Character §9.8.

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
    func resetGameDiceId(entryId: UUID) {
        gameDiceModel.resetGameDiceId(entryId: entryId)
    }
}
