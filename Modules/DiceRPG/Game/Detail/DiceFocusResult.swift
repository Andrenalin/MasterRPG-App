// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DiceFocusResult: View {
    var body: some View {
        FocusedDiceContainer { itemId in
            DiceGameResult(itemId: itemId, isTrailing: true)
        }
    }
}

#Preview(traits: .mockData) {
    DiceFocusResult()
        .environment(DiceDisplayModel())
}
