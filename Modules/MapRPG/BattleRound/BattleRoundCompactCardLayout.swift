// @copyright André Trettin

import SwiftUI

struct BattleRoundCompactCardLayout: View {
    let presentation: BattleRoundCardPresentation
    let actions: BattleRoundActions
    let showCharacter: @MainActor (BattleCombatant) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                BattleRankBadge(
                    rank: presentation.rank,
                    isActive: presentation.isActive
                )
                BattleParticipantColumn(
                    presentation: presentation.attacker,
                    isAttacker: true,
                    isActive: presentation.isActive,
                    tint: presentation.isActive ? .blue : .gray,
                    actions: actions,
                    showCharacter: showCharacter
                )
                BattleAttackerDetails(
                    combatant: presentation.attacker.combatant,
                    isActive: presentation.isActive,
                    actions: actions
                )
                Spacer(minLength: 0)
            }

            Divider()

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "arrow.turn.down.right")
                    .foregroundStyle(.tertiary)
                    .padding(.top, 18)
                    .accessibilityHidden(true)
                BattleDefenderStrip(
                    defenders: presentation.defenders,
                    isActiveEntry: presentation.isActive,
                    actions: actions,
                    showCharacter: showCharacter
                )
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}
