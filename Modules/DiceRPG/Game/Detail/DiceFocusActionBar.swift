// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DiceFocusActionBar: View {
    var body: some View {
        FocusedDiceContainer { itemId in
            DiceGameActionBar(itemId: itemId, showFocusButton: false, canShowPlayer: false, hideOwnDice: false)
        }
    }
}

#Preview(traits: .mockData) {
    DiceFocusActionBar()
        .environment(DiceDisplayModel())
}
