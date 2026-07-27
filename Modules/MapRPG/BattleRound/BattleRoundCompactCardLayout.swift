// @copyright André Trettin

import SwiftUI

struct BattleRoundCompactCardLayout: View {
    let state: BattleRoundCardState
    let presentation: BattleRoundCardPresentation
    let actions: BattleRoundActions
    let showCharacter: @MainActor (BattleCombatant) -> Void
    let selectHitPoints: @MainActor (BattleCombatant) -> Void

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
                    actions: actions,
                    showCharacter: showCharacter,
                    selectHitPoints: selectHitPoints
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
                    state: state,
                    defenders: presentation.defenders,
                    isActiveEntry: presentation.isActive,
                    actions: actions,
                    showCharacter: showCharacter,
                    selectHitPoints: selectHitPoints
                )
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}

#Preview("Compact card layout", traits: .mockData) {
    let model = BattleRoundPreviewData.model()

    if let card = model.cardPresentations.first {
        BattleRoundCompactCardLayout(
            state: BattleRoundCardState(),
            presentation: card,
            actions: .preview(model: model),
            showCharacter: { _ in },
            selectHitPoints: { _ in }
        )
        .frame(width: 340)
        .padding()
    }
}
