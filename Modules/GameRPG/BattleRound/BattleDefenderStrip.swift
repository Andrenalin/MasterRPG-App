// @copyright André Trettin

import MapRPG
import SwiftUI

struct BattleDefenderStrip: View {
    let state: BattleRoundCardState
    let defenders: [BattleRoundParticipantPresentation]
    let isActiveEntry: Bool
    let controller: BattleRoundController
    let showCharacter: @MainActor (BattleCombatant) -> Void
    let selectHitPoints: @MainActor (BattleCombatant) -> Void

    var body: some View {
        if defenders.isEmpty {
            VStack(spacing: 4) {
                Image(systemName: "person.badge.plus")
                    .foregroundStyle(.tertiary)
                Text("Highlight defenders on the map", bundle: .module)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(minWidth: 100, minHeight: 74)
        } else {
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 10) {
                    ForEach(defenders) { defender in
                        BattleParticipantColumn(
                            state: state,
                            presentation: defender,
                            isAttacker: false,
                            isActive: isActiveEntry,
                            tint: isActiveEntry ? .red : .gray,
                            controller: controller,
                            showCharacter: showCharacter,
                            selectHitPoints: selectHitPoints
                        )
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: 280, alignment: .trailing)
        }
    }
}

#Preview("Defenders", traits: .mockData) {
    let controller = BattleRoundController.preview()
    let model = controller.model

    if let card = model.cardPresentations.first {
        BattleDefenderStrip(
            state: BattleRoundCardState(),
            defenders: card.defenders,
            isActiveEntry: card.isActive,
            controller: controller,
            showCharacter: { _ in },
            selectHitPoints: { _ in }
        )
        .padding()
    }
}

#Preview("No defenders") {
    BattleDefenderStrip(
        state: BattleRoundCardState(),
        defenders: [],
        isActiveEntry: false,
        controller: .preview(),
        showCharacter: { _ in },
        selectHitPoints: { _ in }
    )
    .padding()
}
