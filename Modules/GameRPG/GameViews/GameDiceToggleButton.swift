// @copyright André Trettin

import SwiftUI

struct GameDiceToggleButton: View {
    @Environment(GameScreenModel.self) private var gameScreenModel
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        Button {
            withAnimation(accessibilityReduceMotion ? nil : .default) {
                gameScreenModel.showDice.toggle()
            }
        } label: {
            Label {
                Text(gameScreenModel.showDice ? "Hide Dice" : "Show Dice", bundle: .module)
            } icon: {
                Image(systemName: "bag\(gameScreenModel.showDice ? ".fill" : "")")
                    .contentTransition(.symbolEffect(.replace.wholeSymbol))
            }
            .labelStyle(.iconOnly)
        }
        .help(Text(gameScreenModel.showDice ? "Hide Dice" : "Show Dice", bundle: .module))
    }
}

#Preview {
    GameDiceToggleButton()
        .environment(GameScreenModel())
}
