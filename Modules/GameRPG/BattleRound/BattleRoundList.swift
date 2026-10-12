// @copyright André Trettin

import CoreRPG
import Foundation
import MapRPG
import SwiftUI

/// The turn order: a header row, then one card per attacker. The cards are
/// direct rows of the enclosing lazy stack, so each modifier below is written
/// on the row it belongs to.
struct BattleRoundList: View {
    let cards: [BattleRoundCardPresentation]
    let controller: BattleRoundController
    let screenModel: BattleRoundScreenModel

    var body: some View {
        BattleRoundListHeader()

        ForEach(cards) { card in
            BattleRoundCard(
                presentation: card,
                controller: controller,
                screenModel: screenModel
            )
            .equatable()
            .frame(maxWidth: .infinity)
            .padding(.horizontal, BattleRoundSpacing.tight)
            .transition(.move(edge: .trailing).combined(with: .opacity))
#if !os(tvOS)
            // The whole card takes a dropped card; only its handle starts a
            // drag (see `BattleRoundDragHandle`), so the card's buttons and
            // text fields are not inside a drag gesture.
            .dropDestination(for: String.self) { payloads, _ in
                guard let sourceId = payloads.lazy.compactMap(BattleEntryDragPayload.entryId(from:)).first else {
                    return
                }
                screenModel.moveCard(sourceId, onto: card.id, controller: controller)
            }
#endif
            // Drag-to-reorder has no VoiceOver/Switch Control equivalent on
            // its own — these actions give the same reordering capability a
            // non-visual way in.
            .accessibilityAction(named: Text("Move Earlier in Turn Order", bundle: .module)) {
                screenModel.moveCard(card.id, by: -1, controller: controller)
            }
            .accessibilityAction(named: Text("Move Later in Turn Order", bundle: .module)) {
                screenModel.moveCard(card.id, by: 1, controller: controller)
            }
        }
    }
}

private struct BattleRoundListHeader: View {
    var body: some View {
        HStack {
            Text("Turn Order", bundle: .module)
                .font(.headline)

            Spacer()

#if !os(tvOS)
            Label {
                Text("Drag to reorder", bundle: .module)
            } icon: {
                Image(systemName: "line.3.horizontal")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
#endif
        }
        .frame(maxWidth: .infinity)
        .padding(BattleRoundSpacing.standard)
    }
}

#Preview("Turn order", traits: .mockData) {
    let controller = BattleRoundController.preview()
    let model = controller.model
    let screenModel = BattleRoundScreenModel(model: controller.model)

    ScrollView {
        LazyVStack(alignment: .leading, spacing: BattleRoundSpacing.standard) {
            BattleRoundList(
                cards: model.cardPresentations,
                controller: controller,
                screenModel: screenModel
            )
        }
    }
    .environment(AppFocusModel())
}
