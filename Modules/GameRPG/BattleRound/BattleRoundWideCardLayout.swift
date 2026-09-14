// @copyright André Trettin

import MapRPG
import SwiftUI

struct BattleRoundWideCardLayout: View {
    let context: BattleRoundCardLayoutContext

    var body: some View {
        HStack(alignment: .top, spacing: BattleRoundSpacing.loose) {
            BattleRankBadge(
                rank: context.presentation.rank,
                isActive: context.presentation.isActive
            )
            // See CODE_AUDIT §7.2.
            .equatable()
            BattleParticipantColumn(
                state: context.state,
                presentation: context.presentation.attacker,
                isActive: context.presentation.isActive,
                tint: context.presentation.isActive ? .blue : .gray,
                controller: context.controller,
                showCharacter: context.showCharacter,
                selectHitPoints: context.selectHitPoints,
                selectInitiative: context.selectInitiative
            )
            // See CODE_AUDIT §8.3.
            .equatable()
            BattleAttackerDetails(
                combatant: context.presentation.attacker.combatant,
                isActive: context.presentation.isActive,
                controller: context.controller
            )
            // See CODE_AUDIT §7.2.
            .equatable()
            Image(systemName: "arrow.right")
                .foregroundStyle(.tertiary)
                .padding(.top, 20)
                .accessibilityHidden(true)
            BattleDefenderStrip(
                state: context.state,
                defenders: context.presentation.defenders,
                isActiveEntry: context.presentation.isActive,
                controller: context.controller,
                showCharacter: context.showCharacter,
                selectHitPoints: context.selectHitPoints,
                selectInitiative: context.selectInitiative
            )
        }
    }
}

#Preview("Wide card layout", traits: .mockData) {
    let controller = BattleRoundController.preview()
    let model = controller.model

    if let card = model.cardPresentations.first {
        BattleRoundWideCardLayout(
            context: BattleRoundCardLayoutContext(
                state: BattleRoundCardState(),
                presentation: card,
                controller: controller,
                showCharacter: { _ in },
                selectHitPoints: { _ in },
                selectInitiative: { _ in }
            )
        )
        .frame(width: 700)
        .padding()
    }
}
