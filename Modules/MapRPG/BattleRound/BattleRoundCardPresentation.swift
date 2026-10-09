// @copyright André Trettin

import Foundation

public struct BattleRoundParticipantPresentation: Identifiable, Equatable {
    public let combatant: BattleCombatant
    public let rolls: [BattleRollResult]
    public let canReceiveRoll: Bool
    public let isRollRecipient: Bool

    public var id: UUID { combatant.id }
}

public struct BattleRoundCardPresentation: Identifiable, Equatable {
    public let id: UUID
    public let rank: Int
    public let attacker: BattleRoundParticipantPresentation
    public let defenders: [BattleRoundParticipantPresentation]
    public let isActive: Bool
}

/// Every input `cardPresentations` derives from, snapshotted so it can be
/// compared against the previous access instead of unconditionally rebuilt.
/// See CODE_AUDIT §7.2.
struct CardPresentationsCacheKey: Equatable {
    let combatants: [BattleCombatant]
    let entries: [BattleRoundEntry]
    let activeAttackerId: UUID?
    let isPreparingSurprise: Bool
    let rollRecipientId: UUID?
}

public extension BattleRoundModel {
    /// Produces immutable row inputs in one linear pass. Nested views no longer
    /// repeatedly search the observable combatant and roll collections.
    ///
    /// Memoized against `CardPresentationsCacheKey`: this is read on every
    /// live Battle Round tick by `BattleRoundView` regardless of whether
    /// anything battle-related actually changed, so rebuilding unconditionally
    /// would undermine the very `.equatable()` guard `BattleRoundCard` relies
    /// on to skip re-render work downstream — the guard only helps once
    /// producing the array it compares is itself cheap. See CODE_AUDIT §7.2.
    var cardPresentations: [BattleRoundCardPresentation] {
        let activeAttackerId = activeAttackerId
        let isPreparingSurprise = isPreparingSurprise
        let rollRecipientId = masterRollRecipientCombatantId
        let key = CardPresentationsCacheKey(
            combatants: combatants,
            entries: entries,
            activeAttackerId: activeAttackerId,
            isPreparingSurprise: isPreparingSurprise,
            rollRecipientId: rollRecipientId
        )
        if let cache = cardPresentationsCache, cache.key == key {
            return cache.value
        }

        var combatantsById: [UUID: BattleCombatant] = [:]
        combatantsById.reserveCapacity(combatants.count)
        for combatant in combatants {
            combatantsById[combatant.id] = combatant
        }

        let value = entries.enumerated().compactMap { index, entry -> BattleRoundCardPresentation? in
            guard let attacker = combatantsById[entry.attackerId] else { return nil }
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
                    guard let defender = combatantsById[defenderId] else { return nil }
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

        cardPresentationsCache = (key, value)
        return value
    }
}
