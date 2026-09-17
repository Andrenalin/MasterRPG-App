// @copyright André Trettin

import Foundation

// Split out of BattleRoundModel.swift — see CODE_AUDIT §9.13.

// MARK: - Roster mutation

extension BattleRoundModel {
    @discardableResult
    func addCombatant(_ combatant: BattleCombatant) -> Bool {
        guard isPreparingSurprise,
              self.combatant(pinId: combatant.pinId) == nil else {
            return false
        }
        combatants.append(combatant)
        entries.append(BattleRoundEntry(attackerId: combatant.id))
        if combatant.isPlayer {
            retainedPlayerCombatants[combatant.pinId] = combatant
        }
        sortEntries()
        return true
    }

    /// Drops a combatant from the battle entirely — its own turn entry and
    /// every appearance as another entry's defender — rather than just
    /// flagging it dead. The map pin itself is untouched, so highlighting it
    /// again re-adds it as a fresh combatant.
    @discardableResult
    func removeCombatant(_ combatantId: UUID) -> Bool {
        guard let combatant = combatant(id: combatantId) else { return false }
        combatants.removeAll { $0.id == combatantId }
        entries.removeAll { $0.attackerId == combatantId }
        for index in entries.indices {
            entries[index].defenderIds.removeAll { $0 == combatantId }
        }
        if activeAttackerId == combatantId {
            activeAttackerId = nil
            presentedActivePinId = nil
        }
        if rollRecipientCombatantId == combatantId {
            rollRecipientCombatantId = nil
        }
        if combatant.isPlayer {
            retainedPlayerCombatants.removeValue(forKey: combatant.pinId)
            retainedPlayerInitiatives.removeValue(forKey: retentionKey(for: combatant))
        }
        bumpNetworkSequence()
        return true
    }
}

// MARK: - Character assignment & reset

extension BattleRoundModel {
    func retainedGameCharacterId(
        forPlayerPinId pinId: UUID,
        sourceCharacterId: UUID?
    ) -> UUID? {
        guard let retained = retainedPlayerCombatants[pinId],
              retained.sourceCharacterId == sourceCharacterId else {
            return nil
        }
        return retained.gameCharacterId
    }

    @discardableResult
    func assignCharacter(
        combatantId: UUID,
        sourceCharacterId: UUID,
        gameCharacterId: UUID,
        pin: MapPinModel
    ) -> Bool {
        guard let index = combatants.firstIndex(where: { $0.id == combatantId }) else {
            return false
        }
        guard combatants[index].sourceCharacterId != sourceCharacterId
                || combatants[index].gameCharacterId != gameCharacterId
                || combatants[index].pin != pin else {
            return false
        }
        combatants[index].sourceCharacterId = sourceCharacterId
        combatants[index].gameCharacterId = gameCharacterId
        combatants[index].pin = pin
        if combatants[index].isPlayer {
            retainedPlayerCombatants[pin.id] = combatants[index]
        }
        return true
    }

    func reset() {
        isRunning = false
        mapId = nil
        roundCounter = 0
        combatants = []
        entries = []
        activeAttackerId = nil
        rollRecipientCombatantId = nil
        presentedActivePinId = nil
        networkSequence = 0
        retainedPlayerInitiatives = [:]
        retainedPlayerCombatants = [:]
    }
}
