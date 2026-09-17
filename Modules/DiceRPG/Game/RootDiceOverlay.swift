// @copyright André Trettin

import CoreRPG
import SwiftUI

// `hideDice` was previously threaded through from `OverlayGameLayout` but
// never read here — the only call site already gates rendering on
// `!hideDice` before this view is even instantiated, so the parameter was
// dead. Removed rather than wired in, since nothing observed it doing
// anything. See CODE_AUDIT §5.9.
struct RootDiceOverlay: View {
    @Environment(DiceRootModel.self) private var root
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var itemId: UUID = UUID()

    var body: some View {
        DiceOverlay(item: ItemRowTreeModel(itemId: itemId, typeId: root.itemController.config.module), showFocusButton: false, hideOwnDice: valueFor(iOS: false, macOS: false, tvOS: false, visionOS: true))
        .onChange(of: root.gameController.gameModel.focusItemIds, initial: true) {
            withAnimation(Animation.default.reduced(if: reduceMotion)) {
                itemId <=> root.gameController.gameModel.focusItemIds.first ?? UUID()
            }
        }
    }
}

#Preview(traits: .mockData) {
    Rectangle().fill(Color.red.gradient.opacity(0.5)).ignoresSafeArea()
        .overlay {
            RootDiceOverlay()
        }
        .environment(DiceDisplayModel())
}
