// @copyright André Trettin

import CoreRPG
import SwiftUI

struct GameDiceToggleButton: View {
    @Environment(GameScreenModel.self) private var gameScreenModel

    var body: some View {
        @Bindable var gameScreenModel = gameScreenModel
        let _ = Self.printViewChangesOnlyInDebug()
        GameOverlayToggleButton(
            isShown: $gameScreenModel.showDice,
            symbol: "bag",
            title: Text(gameScreenModel.showDice ? "Hide Dice" : "Show Dice", bundle: .module)
        )
    }
}

#Preview {
    GameDiceToggleButton()
        .environment(GameScreenModel())
}
