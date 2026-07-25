// @copyright André Trettin

import SwiftUI

struct BattleRoundWideCardLayout: View {
    let presentation: BattleRoundCardPresentation
    let actions: BattleRoundActions
    let showCharacter: @MainActor (BattleCombatant) -> Void
    let selectHitPoints: @MainActor (BattleCombatant) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
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
                showCharacter: showCharacter,
                selectHitPoints: selectHitPoints
            )
            BattleAttackerDetails(
                combatant: presentation.attacker.combatant,
                isActive: presentation.isActive,
                actions: actions
            )
            Spacer(minLength: 8)
            Image(systemName: "arrow.right")
                .foregroundStyle(.tertiary)
                .padding(.top, 20)
                .accessibilityHidden(true)
            BattleDefenderStrip(
                defenders: presentation.defenders,
                isActiveEntry: presentation.isActive,
                actions: actions,
                showCharacter: showCharacter,
                selectHitPoints: selectHitPoints
            )
        }
    }
}

#Preview("Wide card layout", traits: .mockData) {
    let model = BattleRoundPreviewData.model()

    if let card = model.cardPresentations.first {
        BattleRoundWideCardLayout(
            presentation: card,
            actions: .preview(model: model),
            showCharacter: { _ in },
            selectHitPoints: { _ in }
        )
        .frame(width: 700)
        .padding()
    }
}
