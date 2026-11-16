// @copyright André Trettin

import SwiftUI
import CoreRPG

struct DicePlayerRoot: View {
    /// Slides the player-dice panel fully off-screen to the trailing edge
    /// when hidden. See CODE_AUDIT §8.3.
    private static let hiddenOffset: CGFloat = -200

    @Environment(DiceRootModel.self) private var root
    @Environment(DiceDisplayModel.self) private var diceDisplayModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .trailing) {
            Button {
                withAnimation(Animation.default.reduced(if: reduceMotion)) {
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

            DicePlayer(alignment: .trailing)
                .opacity(diceDisplayModel.showPlayerDice ? 1 : 0)
                .offset(x: diceDisplayModel.showPlayerDice ? 0 : Self.hiddenOffset)
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
