// @copyright André Trettin

import MapRPG
import SwiftUI

struct BattleRoundWideCardLayout: View {
    let state: BattleRoundCardState
    let presentation: BattleRoundCardPresentation
    let controller: BattleRoundController
    let showCharacter: @MainActor (BattleCombatant) -> Void
    let selectHitPoints: @MainActor (BattleCombatant) -> Void
    let selectInitiative: @MainActor (BattleCombatant) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            BattleRankBadge(
                rank: presentation.rank,
                isActive: presentation.isActive
            )
            BattleParticipantColumn(
                state: state,
                presentation: presentation.attacker,
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
            Image(systemName: "arrow.right")
                .foregroundStyle(.tertiary)
                .padding(.top, 20)
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
        }
    }
}

#Preview("Wide card layout", traits: .mockData) {
    let controller = BattleRoundController.preview()
    let model = controller.model

    if let card = model.cardPresentations.first {
        BattleRoundWideCardLayout(
            state: BattleRoundCardState(),
            presentation: card,
            controller: controller,
            showCharacter: { _ in },
            selectHitPoints: { _ in },
            selectInitiative: { _ in }
        )
        .frame(width: 700)
        .padding()
    }
}
