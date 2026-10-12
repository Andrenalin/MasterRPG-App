// @copyright André Trettin

import Foundation

extension BattleRoundModel {
    /// How many rolls one combatant keeps per turn entry. The card shows the
    /// newest ones; without a limit the history of a long battle is compared
    /// and laid out again on every update.
    static let maximumRollsPerCombatant = 20

    @discardableResult
    func addRoll(
        combatantId: UUID,
        total: Int,
        expression: String?,
        outcome: BattleRollOutcome? = nil,
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
                outcome: outcome,
                timestamp: timestamp
            )
        )
        let overflow = entries[entryIndex].rolls.count(where: { $0.combatantId == combatantId })
            - Self.maximumRollsPerCombatant
        if overflow > 0,
           let oldestIndex = entries[entryIndex].rolls.firstIndex(where: { $0.combatantId == combatantId }) {
            entries[entryIndex].rolls.remove(at: oldestIndex)
        }
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
