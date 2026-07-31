// @copyright André Trettin

import Foundation
import MapRPG
import SwiftUI

struct BattleRoundList: View {
    private static let dragPayloadPrefix = "masterrpg-battle-entry:"

    let cards: [BattleRoundCardPresentation]
    let controller: BattleRoundController
    let showCharacter: @MainActor (BattleCombatant) -> Void
    let selectHitPoints: @MainActor (BattleCombatant) -> Void

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        HStack {
            Text("Turn Order", bundle: .module)
                .font(.headline)

            Spacer()

            Label {
                Text("Drag to reorder", bundle: .module)
            } icon: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(8)

        ForEach(cards) { card in
            BattleRoundCard(
                presentation: card,
                controller: controller,
                showCharacter: showCharacter,
                selectHitPoints: selectHitPoints
            )
            .frame(maxWidth: .infinity)
            .transition(.move(edge: .trailing).combined(with: .opacity))
#if !os(tvOS)
            .draggable(dragPayload(for: card.id))
            .dropDestination(for: String.self) { payloads, _ in
                reorder(payloads, over: card.id)
            }
#endif
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(
            accessibilityReduceMotion ? nil : .snappy,
            value: cards
        )
    }

    private func dragPayload(for entryId: UUID) -> String {
        Self.dragPayloadPrefix + entryId.uuidString
    }

    private func reorder(_ payloads: [String], over targetId: UUID) {
        guard let payload = payloads.first,
              payload.hasPrefix(Self.dragPayloadPrefix),
              let sourceId = UUID(
                  uuidString: String(payload.dropFirst(Self.dragPayloadPrefix.count))
              ),
              let sourceIndex = cards.firstIndex(where: { $0.id == sourceId }),
              let targetIndex = cards.firstIndex(where: { $0.id == targetId }) else {
            return
        }
        guard sourceIndex != targetIndex else { return }

        let destination = sourceIndex < targetIndex ? targetIndex + 1 : targetIndex
        controller.moveEntries(IndexSet(integer: sourceIndex), destination)
    }
}

#Preview("Turn order", traits: .mockData) {
    let controller = BattleRoundController.preview()
    let model = controller.model

    ScrollView {
        LazyVStack(alignment: .leading, spacing: 8) {
            BattleRoundList(
                cards: model.cardPresentations,
                controller: controller,
                showCharacter: { _ in },
                selectHitPoints: { _ in }
            )
        }
    }
}
