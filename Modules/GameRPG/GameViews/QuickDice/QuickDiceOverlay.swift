// @copyright André Trettin

import CoreRPG
import DiceRPG
import SwiftUI

/// The player's four quick dice slots, at the bottom trailing edge and as wide as the sidebar.
/// The sidebar stops above it, using `GameScreenModel.quickDiceBottomReservation`.
struct QuickDiceOverlay: View {
    let root: GameRoot

    @Environment(GameScreenModel.self) private var gameScreenModel

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        GlassEffectContainerAll {
            HStack(alignment: .top, spacing: 4) {
                ForEach(0..<QuickDiceSlotsModel.slotCount, id: \.self) { index in
                    QuickDiceSlotView(root: root, index: index)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(8)
        }
#if os(iOS)
        .padding(.trailing, gameScreenModel.chromeTrailingSafeAreaInset)
#endif
        .frame(width: gameScreenModel.sideBarWidth)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: ResolvedAppTheme.panelCornerRadius))
        .shadow(radius: 8)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            gameScreenModel.updateQuickDiceOverlayHeight(height)
        }
        .focusSectionAll()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Quick Dice", bundle: .module))
    }
}

#Preview(traits: .mockData) {
    QuickDiceOverlay(root: .previewFixture(game: .player))
        .environment(GameScreenModel())
}

private struct FilledQuickDicePreview: View {
    let root = GameRoot.previewFixture(game: .player)

    init() {
        let mockDiceId = DiceRootModel.previewDiceId
        root.quickDiceSlots.assign(QuickDiceSlot(source: .dice(diceId: mockDiceId), manualValue: 12), to: 0)
        root.quickDiceSlots.assign(QuickDiceSlot(source: .dice(diceId: mockDiceId)), to: 2)
    }

    var body: some View {
        QuickDiceOverlay(root: root)
            .environment(GameScreenModel())
            .environment(root.diceRoot)
    }
}

#Preview("Filled slots", traits: .mockData) {
    FilledQuickDicePreview()
}
