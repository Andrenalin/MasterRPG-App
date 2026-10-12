// @copyright André Trettin

import MapRPG
import SwiftUI

struct BattleDefenderStrip: View {
    let state: BattleRoundCardState
    let defenders: [BattleRoundParticipantPresentation]
    let isActiveEntry: Bool
    let controller: BattleRoundController
    let screenModel: BattleRoundScreenModel

    @ScaledMetric(relativeTo: .caption2) private var placeholderWidth: CGFloat = 100
    @ScaledMetric(relativeTo: .caption2) private var placeholderHeight: CGFloat = 74
    @ScaledMetric(relativeTo: .caption2) private var maxStripWidth: CGFloat = 280

    var body: some View {
        if defenders.isEmpty {
            VStack(spacing: BattleRoundSpacing.tight) {
                Image(systemName: "person.badge.plus")
                    .foregroundStyle(.tertiary)
                Text("Highlight defenders on the map", bundle: .module)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(minWidth: placeholderWidth, minHeight: placeholderHeight)
        } else {
            ScrollView(.horizontal) {
                // A plain stack: a card has a handful of defenders, and a
                // lazy stack's height depends on which of them are realized,
                // which would let the card — a row of the lazy turn list —
                // change height while scrolling.
                HStack(alignment: .top, spacing: BattleRoundSpacing.relaxed) {
                    ForEach(defenders) { defender in
                        BattleParticipantColumn(
                            state: state,
                            presentation: defender,
                            role: .defender,
                            isActive: isActiveEntry,
                            tint: isActiveEntry ? BattleRoundPalette.defender : BattleRoundPalette.inactive,
                            controller: controller,
                            screenModel: screenModel
                        )
                        .equatable()
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: maxStripWidth, alignment: .trailing)
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
            screenModel: BattleRoundScreenModel(model: model)
        )
        .padding()
    }
}

#Preview("No defenders") {
    let controller = BattleRoundController.preview()

    BattleDefenderStrip(
        state: BattleRoundCardState(),
        defenders: [],
        isActiveEntry: false,
        controller: controller,
        screenModel: BattleRoundScreenModel(model: controller.model)
    )
    .padding()
}
