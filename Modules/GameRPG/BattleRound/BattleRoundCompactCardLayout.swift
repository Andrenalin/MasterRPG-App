// @copyright André Trettin

import MapRPG
import SwiftUI

struct BattleRoundCompactCardLayout: View {
    let state: BattleRoundCardState
    let presentation: BattleRoundCardPresentation
    let controller: BattleRoundController
    let showCharacter: @MainActor (BattleCombatant) -> Void
    let selectHitPoints: @MainActor (BattleCombatant) -> Void
    let selectInitiative: @MainActor (BattleCombatant) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                BattleRankBadge(
                    rank: presentation.rank,
                    isActive: presentation.isActive
                )
                BattleParticipantColumn(
                    state: state,
                    presentation: presentation.attacker,
                    isAttacker: true,
                    isActive: presentation.isActive,
                    tint: presentation.isActive ? .blue : .gray,
                    controller: controller,
                    showCharacter: showCharacter,
                    selectHitPoints: selectHitPoints,
                    selectInitiative: selectInitiative
                )
                BattleAttackerDetails(
                    combatant: presentation.attacker.combatant,
                    isActive: presentation.isActive,
                    controller: controller
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
                    state: state,
                    defenders: presentation.defenders,
                    isActiveEntry: presentation.isActive,
                    controller: controller,
                    showCharacter: showCharacter,
                    selectHitPoints: selectHitPoints,
                    selectInitiative: selectInitiative
                )
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}

#Preview("Compact card layout", traits: .mockData) {
    let controller = BattleRoundController.preview()
    let model = controller.model

    if let card = model.cardPresentations.first {
        BattleRoundCompactCardLayout(
            state: BattleRoundCardState(),
            presentation: card,
            controller: controller,
            showCharacter: { _ in },
            selectHitPoints: { _ in },
            selectInitiative: { _ in }
        )
        .frame(width: 340)
        .padding()
    }
}
