// @copyright André Trettin

import Foundation

// MARK: - Roster mutation

extension BattleRoundModel {
    /// Gives a pin its own turn while the surprise round is being prepared.
    /// A pin that is already on the roster as a mere target (it was
    /// highlighted before it was added) keeps its combatant and only gains
    /// the turn entry; `combatant` is ignored for it.
    @discardableResult
    func addCombatant(_ combatant: BattleCombatant) -> Bool {
        guard canAddCombatant(pinId: combatant.pinId) else { return false }
        return insertTurn(for: combatant)
    }

    /// `addCombatant(_:)` for the "Add Pin to Battle Round" action, which works in any round of
    /// the running battle. The new turn goes where its initiative puts it; the active attacker
    /// and the round counter stay as they are.
    @discardableResult
    func joinCombatant(_ combatant: BattleCombatant) -> Bool {
        guard isRunning, lacksTurn(pinId: combatant.pinId) else { return false }
        return insertTurn(for: combatant)
    }

    private func insertTurn(for combatant: BattleCombatant) -> Bool {
        let combatantId: UUID
        if let existing = self.combatant(pinId: combatant.pinId) {
            combatantId = existing.id
        } else {
            combatants.append(combatant)
            combatantId = combatant.id
            if combatant.isPlayer {
                retainedPlayerCombatants[combatant.pinId] = combatant
            }
        }
        entries.append(BattleRoundEntry(attackerId: combatantId))
        repositionEntry(for: combatantId)
        return true
    }

    /// Drops a combatant from the battle entirely — its own turn entry and
    /// every appearance as another entry's defender — rather than just
    /// flagging it dead. The map pin itself is untouched, so highlighting it
    /// again re-adds it as a fresh combatant.
    @discardableResult
    func removeCombatant(_ combatantId: UUID) -> Bool {
        guard let combatant = combatant(id: combatantId) else { return false }
        // The active attacker leaves: its turn passes on to the next living
        // attacker, as "Next Turn" would. Clearing the turn instead sent the
        // battle back to the top of the order (and, in round 0, back into
        // preparing the surprise round).
        if activeAttackerId == combatantId {
            let index = entries.firstIndex { $0.attackerId == combatantId }
            if index.map({ advanceTurn(after: $0, excluding: combatantId) }) != true {
                activeAttackerId = nil
                presentedActivePinId = nil
            }
        }
        combatants.removeAll { $0.id == combatantId }
        entries.removeAll { $0.attackerId == combatantId }
        for index in entries.indices {
            entries[index].defenderIds.removeAll { $0 == combatantId }
        }
        if rollRecipientCombatantId == combatantId {
            rollRecipientCombatantId = activeAttackerId
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
