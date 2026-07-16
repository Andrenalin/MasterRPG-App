// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DiceFocusActionBar: View {
    @Environment(DiceRootModel.self) private var root
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var itemId = UUID()

    var body: some View {
        DiceGameActionBar(itemId: itemId, showFocusButton: false, canShowPlayer: false, hideOwnDice: false)
            .onChange(of: root.gameController.gameModel.focusItemIds, initial: true) {
                withAnimation(reduceMotion ? nil : .default) {
                    itemId <=> root.gameController.gameModel.focusItemIds.first ?? UUID()
                }
            }
    }
}

#Preview(traits: .mockData) {
    DiceFocusActionBar()
        .environment(DiceDisplayModel())
}
