// @copyright André Trettin

import SwiftUI

struct BattleDefenderStrip: View {
    let model: BattleModel
    let defenders: [BattleRoundParticipantPresentation]
    let isActiveEntry: Bool
    let actions: BattleRoundActions
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
                            model: model,
                            presentation: defender,
                            isAttacker: false,
                            isActive: isActiveEntry,
                            tint: isActiveEntry ? .red : .gray,
                            actions: actions,
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
    let model = BattleRoundPreviewData.model()

    if let card = model.cardPresentations.first {
        BattleDefenderStrip(
            model: BattleModel(),
            defenders: card.defenders,
            isActiveEntry: card.isActive,
            actions: .preview(model: model),
            showCharacter: { _ in },
            selectHitPoints: { _ in }
        )
        .padding()
    }
}

#Preview("No defenders") {
    let model = BattleRoundPreviewData.model()

    BattleDefenderStrip(
        model: BattleModel(),
        defenders: [],
        isActiveEntry: false,
        actions: .preview(model: model),
        showCharacter: { _ in },
        selectHitPoints: { _ in }
    )
    .padding()
}
