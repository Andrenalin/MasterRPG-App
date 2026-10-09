// @copyright André Trettin

import MapRPG
import SwiftUI

/// The attacker's status row (player, dead, highlighted) shared by the wide
/// and compact battle cards.
struct BattleAttackerStatusIcons: View, Equatable {
    let combatant: BattleCombatant
    let isActive: Bool
    var showsDead = true

    var body: some View {
        HStack(spacing: BattleRoundSpacing.tight) {
            if combatant.isPlayer {
                Image(systemName: "person.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text("Player", bundle: .module))
            }
            if showsDead, combatant.isDead {
                Image(systemName: "person.slash")
                    .foregroundStyle(.red)
                    .accessibilityLabel(Text("Dead", bundle: .module))
            }
            if isActive {
                Image(systemName: "scope")
                    .foregroundStyle(.blue)
                    .accessibilityLabel(Text("Highlighted", bundle: .module))
            }
        }
    }
}

#Preview("Attacker status") {
    let model = BattleRoundController.preview().model

    if let card = model.cardPresentations.first {
        BattleAttackerStatusIcons(
            combatant: card.attacker.combatant,
            isActive: card.isActive
        )
        .padding()
    }
}
