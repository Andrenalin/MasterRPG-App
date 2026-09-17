// @copyright André Trettin

import Foundation

// Split out of BattleRoundModel.swift — see CODE_AUDIT §9.13.

extension BattleRoundModel {
    @discardableResult
    func addRoll(
        combatantId: UUID,
        total: Int,
        expression: String?,
        timestamp: Date = .now
    ) -> Bool {
        let entryIndex: Int
        if let activeAttackerId,
           let activeIndex = entries.firstIndex(where: { $0.attackerId == activeAttackerId }) {
            let entry = entries[activeIndex]
            guard combatantId == activeAttackerId
                    || entry.defenderIds.contains(combatantId) else {
                return false
            }
            entryIndex = activeIndex
        } else {
            guard isPreparingSurprise,
                  let surpriseIndex = entries.firstIndex(where: {
                      $0.attackerId == combatantId
                  }) else {
                return false
            }
            entryIndex = surpriseIndex
        }
        entries[entryIndex].rolls.append(
            BattleRollResult(
                combatantId: combatantId,
                total: total,
                expression: expression,
                timestamp: timestamp
            )
        )
        return true
    }

    @discardableResult
    func selectRollRecipient(_ combatantId: UUID) -> Bool {
        if isPreparingSurprise {
            guard combatant(id: combatantId)?.isPlayer == false,
                  entries.contains(where: { $0.attackerId == combatantId }),
                  rollRecipientCombatantId != combatantId else {
                return false
            }
            rollRecipientCombatantId = combatantId
            return true
        }
        guard let activeAttackerId,
              let entry = activeEntry,
              combatant(id: combatantId)?.isPlayer == false,
              combatantId == activeAttackerId || entry.defenderIds.contains(combatantId),
              rollRecipientCombatantId != combatantId else {
            return false
        }
        rollRecipientCombatantId = combatantId
        return true
    }
}
