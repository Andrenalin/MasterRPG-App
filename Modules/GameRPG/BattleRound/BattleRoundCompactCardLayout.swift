// @copyright André Trettin

import MapRPG
import SwiftUI

/// The one battle card layout, used by the sidebar and the battle window.
struct BattleRoundCompactCardLayout: View {
    let context: BattleRoundCardLayoutContext

    /// Lines the "targets" arrow up with the defenders' avatars, below their
    /// name row. Scales with the text of that row.
    @ScaledMetric(relativeTo: .caption2) private var targetArrowTopInset: CGFloat = 18

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
                    // `.equatable()` skips this leaf when an unrelated part
                    // of the same card changes.
                    .equatable()
                    .labelStyle(.iconOnly)
                    BattleRankBadge(
                        rank: context.presentation.rank,
                        isActive: context.presentation.isActive
                    )
                    .equatable()
#if !os(tvOS)
                    BattleRoundDragHandle(
                        cardId: context.presentation.id,
                        name: context.presentation.attacker.combatant.name
                    )
                    .equatable()
                    .padding(.top, BattleRoundSpacing.tight)
#endif
                }
                BattleParticipantColumn(
                    state: context.state,
                    presentation: context.presentation.attacker,
                    role: .attacker,
                    isActive: context.presentation.isActive,
                    tint: context.presentation.isActive ? BattleRoundPalette.attacker : BattleRoundPalette.inactive,
                    controller: context.controller,
                    screenModel: context.screenModel
                )
                .equatable()
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            BattleAttackerConfigRows(
                combatant: context.presentation.attacker.combatant,
                state: context.state,
                controller: context.controller,
                screenModel: context.screenModel
            )

            Divider()

            HStack(alignment: .top, spacing: BattleRoundSpacing.standard) {
                Image(systemName: "arrow.turn.down.right")
                    .foregroundStyle(.tertiary)
                    .padding(.top, targetArrowTopInset)
                    .accessibilityHidden(true)
                BattleDefenderStrip(
                    state: context.state,
                    defenders: context.presentation.defenders,
                    isActiveEntry: context.presentation.isActive,
                    controller: context.controller,
                    screenModel: context.screenModel
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
                screenModel: BattleRoundScreenModel(model: model)
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
                screenModel: BattleRoundScreenModel(model: model)
            )
        )
        .frame(width: 340)
        .padding()
    }
}
