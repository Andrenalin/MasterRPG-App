// @copyright André Trettin

import CoreRPG
import SwiftUI

/// Rolls a dice set and shares the result. One button for `DiceGameActionBar` and, through
/// `DiceFocusRollButton`, the dice popover of the 3D table.
struct DiceRollButton: View {
    let itemId: UUID

    @Environment(DiceRootModel.self) private var root
    @Environment(DiceDisplayModel.self) private var diceDisplayModel

    @Environment(\.networkActions) private var networkActions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            if diceDisplayModel.isEditing {
                withAnimation(Animation.default.reduced(if: reduceMotion)) {
                    diceDisplayModel.isEditing = false
                }
            }
            withAnimation(Animation.default.reduced(if: reduceMotion)) {
                root.gameController.rollDice(itemId: itemId, networkActions: networkActions)
            }
#if !os(tvOS)
            root.donateRoll(of: itemId)
#endif
        } label: {
            Label {
                Text("Roll dice", bundle: .module)
            } icon: {
                Image(systemName: diceIcon)
                    .contentTransition(.symbolEffect(.replace.wholeSymbol))
            }
            .labelStyle(.iconOnly)
        }
        .gameOverlayControlStyle()
    }

    private var diceIcon: String {
        root.gameController.hasResults(itemId: itemId) ? root.itemController.config.module.icon + ".fill" : root.itemController.config.module.icon
    }
}

#Preview(traits: .mockData) {
    DiceRollButton(itemId: DiceModel.previewId)
        .environment(DiceDisplayModel())
}
