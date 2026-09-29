// @copyright André Trettin

import Foundation
import SwiftUI

// Split out of BattleRoundModel.swift — see CODE_AUDIT §9.13.

// MARK: - Battle lifecycle

extension BattleRoundModel {
    func begin(
        mapId: UUID,
        players: [BattleCombatant],
        roomCombatants: [BattleCombatant],
        initiativeOrder: BattleInitiativeOrder
    ) {
        rememberPlayerInitiatives()
        self.mapId = mapId
        self.initiativeOrder = initiativeOrder
        isRunning = true
        roundCounter = 0
        activeAttackerId = nil
        rollRecipientCombatantId = nil
        presentedActivePinId = nil

        let refreshedPlayers = players.map { incoming in
            guard var retained = retainedPlayerCombatants[incoming.pinId],
                  retained.sourceCharacterId == incoming.sourceCharacterId else {
                var newPlayer = incoming
                newPlayer.initiative = retainedPlayerInitiatives[retentionKey(for: incoming)]
                    ?? incoming.initiative
                retainedPlayerCombatants[incoming.pinId] = newPlayer
                return newPlayer
            }
            retained.pin = incoming.pin
            retained.initiative = retainedPlayerInitiatives[retentionKey(for: incoming)]
                ?? retained.initiative
                ?? incoming.initiative
            retainedPlayerCombatants[incoming.pinId] = retained
            return retained
        }

        let allCombatants = refreshedPlayers + roomCombatants
        combatants = allCombatants
        entries = allCombatants.map { BattleRoundEntry(attackerId: $0.id) }
        sortEntries()
        bumpNetworkSequence()
    }

    func end() {
        rememberPlayerInitiatives()
        isRunning = false
        roundCounter = 0
        activeAttackerId = nil
        rollRecipientCombatantId = nil
        presentedActivePinId = nil
        bumpNetworkSequence()
    }

    private func rememberPlayerInitiatives() {
        for combatant in combatants where combatant.isPlayer {
            retainedPlayerCombatants[combatant.pinId] = combatant
            retainedPlayerInitiatives[retentionKey(for: combatant)] = combatant.initiative
        }
    }
}

// MARK: - Initiative & value configuration

extension BattleRoundModel {
    @discardableResult
    func setInitiative(_ value: Int?, for combatantId: UUID) -> Bool {
        guard let index = combatants.firstIndex(where: { $0.id == combatantId }) else {
            return false
        }
        let normalized = value.map { max(1, $0) }
        guard combatants[index].initiative != normalized else { return false }
        combatants[index].initiative = normalized
        if combatants[index].isPlayer {
            retainedPlayerInitiatives[retentionKey(for: combatants[index])] = normalized
        }
        sortEntries()
        return true
    }

    @discardableResult
    func adjustInitiative(by amount: Int, for combatantId: UUID) -> Bool {
        guard let combatant = combatant(id: combatantId) else { return false }
        return setInitiative(max(1, (combatant.initiative ?? 1) + amount), for: combatantId)
    }

    @discardableResult
    func setInitiativeOrder(_ order: BattleInitiativeOrder) -> Bool {
        guard initiativeOrder != order else { return false }
        initiativeOrder = order
        sortEntries()
        return true
    }

    @discardableResult
    func setValueEntry(
        _ entryId: UUID?,
        kind: BattleValueKind,
        for combatantId: UUID
    ) -> Bool {
        guard let index = combatants.firstIndex(where: { $0.id == combatantId }) else {
            return false
        }
        switch kind {
        case .initiative:
            guard combatants[index].initiativeEntryId != entryId else { return false }
            combatants[index].initiativeEntryId = entryId
        case .hitPoints:
            guard combatants[index].hitPointsEntryId != entryId else { return false }
            combatants[index].hitPointsEntryId = entryId
        }
        if combatants[index].isPlayer {
            retainedPlayerCombatants[combatants[index].pinId] = combatants[index]
        }
        return true
    }

    func moveEntries(from source: IndexSet, to destination: Int) {
        entries.move(fromOffsets: source, toOffset: destination)
    }
}

// MARK: - Turn progression

extension BattleRoundModel {
    @discardableResult
    func activateAttacker(_ combatantId: UUID) -> Bool {
        guard isRunning,
              entries.contains(where: { $0.attackerId == combatantId }),
              activeAttackerId != combatantId else {
            return false
        }
        activeAttackerId = combatantId
        rollRecipientCombatantId = combatantId
        presentedActivePinId = combatant(id: combatantId)?.pinId
        bumpNetworkSequence()
        return true
    }

    @discardableResult
    func nextAttacker() -> Bool {
        guard isRunning, !entries.isEmpty else { return false }
        guard let activeAttackerId,
              let index = entries.firstIndex(where: { $0.attackerId == activeAttackerId }) else {
            return activateAttacker(firstLivingAttackerId(from: 0) ?? entries[0].attackerId)
        }
        if let nextId = firstLivingAttackerId(from: index + 1) {
            return activateAttacker(nextId)
        }
        // Nobody alive remains later in this round's order: advance the round
        // and search again from the top, so a fallen combatant is skipped
        // there too instead of ending up active again.
        roundCounter += 1
        let firstId = firstLivingAttackerId(from: 0) ?? entries[0].attackerId
        self.activeAttackerId = firstId
        rollRecipientCombatantId = firstId
        presentedActivePinId = combatant(id: firstId)?.pinId
        bumpNetworkSequence()
        return true
    }

    /// The id of the first entry's attacker at or after `startIndex` who
    /// isn't dead. `nil` when nobody in that range is alive (e.g. everyone
    /// remaining in the round has fallen).
    private func firstLivingAttackerId(from startIndex: Int) -> UUID? {
        guard startIndex < entries.count else { return nil }
        for index in startIndex..<entries.count {
            guard let attacker = attacker(for: entries[index]), !attacker.isDead else { continue }
            return entries[index].attackerId
        }
        return nil
    }

    /// Drops a fallen combatant from every entry's target list. `synchronize(pins:)` only
    /// recomputes the *active* entry's `defenderIds`, so the other attackers kept it and
    /// highlighted it again on their next turn. See CODE_AUDIT_19 §5.8.
    @discardableResult
    func removeDefender(_ combatantId: UUID) -> Bool {
        var changed = false
        for index in entries.indices where entries[index].defenderIds.contains(combatantId) {
            entries[index].defenderIds.removeAll { $0 == combatantId }
            changed = true
        }
        if rollRecipientCombatantId == combatantId, rollRecipientCombatantId != activeAttackerId {
            rollRecipientCombatantId = activeAttackerId
            changed = true
        }
        if changed {
            bumpNetworkSequence()
        }
        return changed
    }

    @discardableResult
    func nextRound() -> Bool {
        guard isRunning else { return false }
        roundCounter += 1
        // Skip fallen combatants, as `nextAttacker()` does. See CODE_AUDIT_19 §5.8.
        activeAttackerId = firstLivingAttackerId(from: 0) ?? entries.first?.attackerId
        rollRecipientCombatantId = activeAttackerId
        presentedActivePinId = activeAttackerId.flatMap { combatant(id: $0)?.pinId }
        bumpNetworkSequence()
        return true
    }

    @discardableResult
    func synchronize(
        pins: [MapPinModel],
        additionalDefenders: [BattleCombatant] = []
    ) -> Bool {
        guard isRunning else { return false }
        var changed = false
        // Last-wins rather than a trapping uniqueKeysWithValues — `pins`
        // ultimately comes from a decoded network payload. See CODE_AUDIT_Game §5.5.
        let pinsById = Dictionary(pins.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })

        for index in combatants.indices {
            guard let pin = pinsById[combatants[index].pinId], combatants[index].pin != pin else {
                continue
            }
            combatants[index].pin = pin
            changed = true
        }

        for defender in additionalDefenders where combatant(pinId: defender.pinId) == nil {
            combatants.append(defender)
            changed = true
        }

        guard let activeAttackerId,
              let entryIndex = entries.firstIndex(where: { $0.attackerId == activeAttackerId }),
              let attacker = combatant(id: activeAttackerId) else {
            return changed
        }

        let defenderIds = combatants
            .filter { $0.id != activeAttackerId && $0.isHighlighted }
            .map(\.id)
        if entries[entryIndex].defenderIds != defenderIds {
            entries[entryIndex].defenderIds = defenderIds
            changed = true
        }
        if let rollRecipientCombatantId,
           rollRecipientCombatantId != activeAttackerId,
           !defenderIds.contains(rollRecipientCombatantId) {
            self.rollRecipientCombatantId = activeAttackerId
            changed = true
        }

        // The active attacker is never a defender and must remain highlighted.
        if !attacker.isHighlighted {
            changed = true
        }
        return changed
    }
}
