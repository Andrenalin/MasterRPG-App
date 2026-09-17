// @copyright André Trettin

import CoreRPG
import SwiftUI

/// Shared by `DiceFocusActionBar`/`DiceFocusResult`/`DiceFocusRoll`, which
/// each previously duplicated this same "track the currently focused dice
/// itemId" state and `onChange` verbatim. See CODE_AUDIT §8.2.
struct FocusedDiceContainer<Content: View>: View {
    @ViewBuilder let content: (UUID) -> Content

    @Environment(DiceRootModel.self) private var root
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var itemId = UUID()

    var body: some View {
        content(itemId)
            .onChange(of: root.gameController.gameModel.focusItemIds, initial: true) {
                withAnimation(Animation.default.reduced(if: reduceMotion)) {
                    itemId <=> root.gameController.gameModel.focusItemIds.first ?? UUID()
                }
            }
    }
}
