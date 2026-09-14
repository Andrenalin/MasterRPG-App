// @copyright André Trettin

import Foundation
import MapRPG
import SwiftUI

struct BattleRoundList: View {
    private static let dragPayloadPrefix = "masterrpg-battle-entry:"

    let cards: [BattleRoundCardPresentation]
    let controller: BattleRoundController
    let screenModel: BattleRoundScreenModel
    
    let showCharacter: @MainActor (BattleCombatant) -> Void
    let selectHitPoints: @MainActor (BattleCombatant) -> Void
    let selectInitiative: @MainActor (BattleCombatant) -> Void

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
        .padding(BattleRoundSpacing.standard)

        ForEach(cards.enumerated(), id: \.element.id) { index, card in
            BattleRoundCard(
                presentation: card,
                controller: controller,
                cardLayout: screenModel.cardLayout,
                showCharacter: showCharacter,
                selectHitPoints: selectHitPoints,
                selectInitiative: selectInitiative
            )
            .equatable()
            .frame(maxWidth: .infinity)
            .transition(.move(edge: .trailing).combined(with: .opacity))
#if !os(tvOS)
            .draggable(dragPayload(for: card.id))
            .dropDestination(for: String.self) { payloads, _ in
                reorder(payloads, over: card.id)
            }
#endif
            // Drag-to-reorder has no VoiceOver/Switch Control equivalent on
            // its own — these actions give the same reordering capability a
            // non-visual way in. See CODE_AUDIT §8.2.
            .accessibilityAction(named: Text("Move Earlier in Turn Order", bundle: .module)) {
                moveEntry(at: index, by: -1)
            }
            .accessibilityAction(named: Text("Move Later in Turn Order", bundle: .module)) {
                moveEntry(at: index, by: 1)
            }
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

    /// Non-drag equivalent of `reorder(_:over:)` for VoiceOver/Switch
    /// Control — swaps the entry at `index` with its neighbor one position
    /// earlier (`offset == -1`) or later (`offset == 1`) in the turn order.
    /// A no-op at either end of the list, where that neighbor doesn't exist.
    /// See CODE_AUDIT §8.2.
    private func moveEntry(at index: Int, by offset: Int) {
        let targetIndex = index + offset
        guard cards.indices.contains(index), cards.indices.contains(targetIndex) else { return }
        controller.moveEntries(IndexSet(integer: index), Self.moveDestination(from: index, to: targetIndex))
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

        controller.moveEntries(IndexSet(integer: sourceIndex), Self.moveDestination(from: sourceIndex, to: targetIndex))
    }

    /// Shared by both reorder paths (drag-and-drop and the VoiceOver
    /// accessibility actions above): `IndexSet`-based moves expect a
    /// destination index that's one past `to` whenever the move is going
    /// forward. See CODE_AUDIT §9.4.
    private static func moveDestination(from: Int, to: Int) -> Int {
        to > from ? to + 1 : to
    }
}

#Preview("Turn order", traits: .mockData) {
    let controller = BattleRoundController.preview()
    let model = controller.model
    let screenModel = BattleRoundScreenModel(model: controller.model, layout: .wide)

    ScrollView {
        LazyVStack(alignment: .leading, spacing: BattleRoundSpacing.standard) {
            BattleRoundList(
                cards: model.cardPresentations,
                controller: controller,
                screenModel: screenModel,
                showCharacter: { _ in },
                selectHitPoints: { _ in },
                selectInitiative: { _ in }
            )
        }
    }
}
