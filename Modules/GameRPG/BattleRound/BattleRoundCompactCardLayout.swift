// @copyright André Trettin

import MapRPG
import SwiftUI

/// The one battle card layout, used by the sidebar and the battle window.
struct BattleRoundCompactCardLayout: View {
    let context: BattleRoundCardLayoutContext

    var body: some View {
        VStack(alignment: .leading, spacing: BattleRoundSpacing.standard) {
            HStack(alignment: .top, spacing: BattleRoundSpacing.relaxed) {
                // The badge brings its own top padding, which is the gap to
                // the activate button here.
                VStack(spacing: 0) {
                    BattleActivateAttackerButton(
                        combatant: context.presentation.attacker.combatant,
                        isActive: context.presentation.isActive,
                        controller: context.controller
                    )
                    // See CODE_AUDIT §7.2.
                    .equatable()
                    .labelStyle(.iconOnly)
                    BattleRankBadge(
                        rank: context.presentation.rank,
                        isActive: context.presentation.isActive
                    )
                    // See CODE_AUDIT §7.2.
                    .equatable()
                }
                BattleParticipantColumn(
                    state: context.state,
                    presentation: context.presentation.attacker,
                    role: .attacker,
                    isActive: context.presentation.isActive,
                    tint: context.presentation.isActive ? .blue : .gray,
                    controller: context.controller,
                    showCharacter: context.showCharacter
                )
                // See CODE_AUDIT §8.3.
                .equatable()
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            BattleAttackerConfigRows(
                combatant: context.presentation.attacker.combatant,
                state: context.state,
                controller: context.controller,
                selectHitPoints: context.selectHitPoints,
                selectInitiative: context.selectInitiative
            )

            Divider()

            HStack(alignment: .top, spacing: BattleRoundSpacing.standard) {
                Image(systemName: "arrow.turn.down.right")
                    .foregroundStyle(.tertiary)
                    .padding(.top, 18)
                    .accessibilityHidden(true)
                BattleDefenderStrip(
                    state: context.state,
                    defenders: context.presentation.defenders,
                    isActiveEntry: context.presentation.isActive,
                    controller: context.controller,
                    showCharacter: context.showCharacter
                )
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}

#Preview("Compact card, config rows hidden", traits: .mockData) {
    let controller = BattleRoundController.preview()
    let model = controller.model
    let state: BattleRoundCardState = {
        let state = BattleRoundCardState()
        state.setValueRow(.initiative, isShown: false)
        state.setValueRow(.hitPoints, isShown: false)
        return state
    }()

    if let card = model.cardPresentations.first {
        BattleRoundCompactCardLayout(
            context: BattleRoundCardLayoutContext(
                state: state,
                presentation: card,
                controller: controller,
                showCharacter: { _ in },
                selectHitPoints: { _ in },
                selectInitiative: { _ in }
            )
        )
        .frame(width: 340)
        .padding()
    }
}

#Preview("Compact card layout", traits: .mockData) {
    let controller = BattleRoundController.preview()
    let model = controller.model

    if let card = model.cardPresentations.first {
        BattleRoundCompactCardLayout(
            context: BattleRoundCardLayoutContext(
                state: BattleRoundCardState(),
                presentation: card,
                controller: controller,
                showCharacter: { _ in },
                selectHitPoints: { _ in },
                selectInitiative: { _ in }
            )
        )
        .frame(width: 340)
        .padding()
    }
}
