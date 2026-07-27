// @copyright André Trettin

import Foundation

public enum BattleRoundCardLayout: Sendable {
    case compact
    case wide
}

struct BattleRoundParticipantPresentation: Identifiable, Equatable {
    let combatant: BattleCombatant
    let rolls: [BattleRollResult]
    let canReceiveRoll: Bool
    let isRollRecipient: Bool

    var id: UUID { combatant.id }
}

struct BattleRoundCardPresentation: Identifiable, Equatable {
    let id: UUID
    let rank: Int
    let attacker: BattleRoundParticipantPresentation
    let defenders: [BattleRoundParticipantPresentation]
    let isActive: Bool
}

extension BattleRoundModel {
    /// Produces immutable row inputs in one linear pass. Nested views no longer
    /// repeatedly search the observable combatant and roll collections.
    var cardPresentations: [BattleRoundCardPresentation] {
        var combatantsByID: [UUID: BattleCombatant] = [:]
        combatantsByID.reserveCapacity(combatants.count)
        for combatant in combatants {
            combatantsByID[combatant.id] = combatant
        }

        let activeAttackerId = activeAttackerId
        let isPreparingSurprise = isPreparingSurprise
        let rollRecipientId = masterRollRecipientCombatantId

        return entries.enumerated().compactMap { index, entry -> BattleRoundCardPresentation? in
            guard let attacker = combatantsByID[entry.attackerId] else { return nil }
            let isActive = activeAttackerId == attacker.id
            let rollsByCombatant = Dictionary(grouping: entry.rolls, by: \.combatantId)

            let attackerPresentation = BattleRoundParticipantPresentation(
                combatant: attacker,
                rolls: rollsByCombatant[attacker.id] ?? [],
                canReceiveRoll: !attacker.isPlayer && (isActive || isPreparingSurprise),
                isRollRecipient: rollRecipientId == attacker.id
            )
            let defenderPresentations: [BattleRoundParticipantPresentation] =
                entry.defenderIds.compactMap { defenderId -> BattleRoundParticipantPresentation? in
                    guard let defender = combatantsByID[defenderId] else { return nil }
                    return BattleRoundParticipantPresentation(
                        combatant: defender,
                        rolls: rollsByCombatant[defender.id] ?? [],
                        canReceiveRoll: isActive && !defender.isPlayer,
                        isRollRecipient: rollRecipientId == defender.id
                    )
                }

            return BattleRoundCardPresentation(
                id: entry.id,
                rank: index + 1,
                attacker: attackerPresentation,
                defenders: defenderPresentations,
                isActive: isActive
            )
        }
    }
}
