// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DiceFocusRollButton: View {
    @Environment(DiceRootModel.self) private var root

    var body: some View {
        FocusedDiceContainer { itemId in
            // Like `DiceGameActionBar`: another player's shared dice are not this device's to roll.
            if !root.gameController.isPlayerDice(itemId: itemId) {
                DiceRollButton(itemId: itemId)
            }
        }
    }
}

#Preview(traits: .mockData) {
    DiceFocusRollButton()
        .environment(DiceDisplayModel())
}
