// @copyright André Trettin

import CoreRPG
import MapRPG
import SwiftUI

/// The scrolling part of the battle round screen: the turn order or the empty
/// state. The settings panel is not part of it, it is pinned above
/// (`BattleRoundStickySettings`).
///
/// A view of its own so the scroll position is this view's state. On the
/// screen's root view every position update re-ran the whole screen body.
struct BattleRoundScrollContent: View {
    let controller: BattleRoundController
    let screenModel: BattleRoundScreenModel

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var scrollPosition = ScrollPosition()

    var body: some View {
        let model = controller.model
        let showsCards = model.isRunning && !model.entries.isEmpty
        let cards = showsCards ? model.cardPresentations(hidingPins: controller.hiddenPinIds) : []
        let isConfigurationExpanded = screenModel.isConfigurationExpanded

        ScrollView {
            LazyVStack {
                if showsCards {
                    BattleRoundList(
                        cards: cards,
                        controller: controller,
                        screenModel: screenModel
                    )
                } else {
                    BattleRoundEmptyState(
                        isRunning: model.isRunning,
                        start: { controller.start() }
                    )
                    // Centred in the visible area. A lazy stack in a scroll
                    // view gives its rows no height to fill, so the state
                    // takes the scroll view's own. With the settings panel
                    // expanded above it keeps its natural height instead, so
                    // "Start Battle" stays next to the settings.
                    .applyIf(!isConfigurationExpanded) {
                        $0.containerRelativeFrame(.vertical)
                    }
                }
            }
            .scrollTargetLayout()
            .animation(accessibilityReduceMotion ? nil : .snappy, value: cards)
        }
        .scrollPosition($scrollPosition)
        // The turn moved on: bring the new attacker's card to the
        // top. The previous card collapses its character sheet in the
        // same update, which would otherwise leave the list wherever
        // that sheet had pushed it.
        .onChange(of: screenModel.activeCardId) { _, cardId in
            guard let cardId else { return }
            withAnimation(accessibilityReduceMotion ? nil : .default) {
                scrollPosition.scrollTo(id: cardId, anchor: .top)
            }
        }
    }
}

#Preview("Battle list", traits: .mockData) {
    let controller = BattleRoundController.preview()

    BattleRoundScrollContent(
        controller: controller,
        screenModel: BattleRoundScreenModel(model: controller.model)
    )
    .environment(AppFocusModel())
}
