// @copyright André Trettin

import SwiftUI
import CoreRPG

struct DicePlayerRoot: View {
    @Environment(DiceRootModel.self) private var root
    @Environment(DiceDisplayModel.self) private var diceDisplayModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .trailing) {
            Button {
                withAnimation(reduceMotion ? nil : .default) {
                    diceDisplayModel.showPlayerDice.toggle()
                }
            } label: {
                Label {
                    if diceDisplayModel.showPlayerDice {
                        Text("Hide player dice", bundle: .module)
                    } else {
                        Text("Show player dice", bundle: .module)
                    }
                } icon: {
                    Image(systemName: root.itemController.config.module.icon)
                }
                .labelStyle(.iconOnly)
                .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)

            DicePlayer(filterout: root.gameController.gameModel.focusItemIds.first ?? UUID(), alignment: .trailing)
                .opacity(diceDisplayModel.showPlayerDice ? 1 : 0)
                .offset(x: diceDisplayModel.showPlayerDice ? 0 : -200)
                .allowsHitTesting(diceDisplayModel.showPlayerDice)
                .accessibilityHidden(!diceDisplayModel.showPlayerDice)
        }
    }
}

#Preview {
    DicePlayerRoot()
        .environment(DiceRootModel.preview)
        .environment(DiceDisplayModel(showPlayerDice: true))
}
