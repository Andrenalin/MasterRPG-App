// @copyright André Trettin

import CoreRPG
import SwiftUI

struct GameQuickDiceToggleButton: View {
    @Environment(GameScreenModel.self) private var gameScreenModel

    var body: some View {
        @Bindable var gameScreenModel = gameScreenModel
        let _ = Self.printViewChangesOnlyInDebug()
        GameOverlayToggleButton(
            isShown: $gameScreenModel.showQuickDice,
            symbol: "square.grid.2x2",
            title: Text(gameScreenModel.showQuickDice ? "Hide Quick Dice" : "Show Quick Dice", bundle: .module)
        )
    }
}

#Preview {
    GameQuickDiceToggleButton()
        .environment(GameScreenModel())
}
