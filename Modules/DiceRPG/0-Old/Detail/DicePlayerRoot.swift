// @copyright André Trettin

import SwiftUI
import CoreRPG

struct DicePlayerRoot: View {
    @Environment(DiceRootModel.self) private var root
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showPlayerDice = true

    var body: some View {
        VStack(alignment: .trailing) {
            Button {
                withAnimation(reduceMotion ? nil : .default) {
                    showPlayerDice.toggle()
                }
            } label: {
                Label {
                    if showPlayerDice {
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
                .opacity(showPlayerDice ? 1 : 0)
                .offset(x: showPlayerDice ? 0 : -200)
                .allowsHitTesting(showPlayerDice)
                .accessibilityHidden(!showPlayerDice)
        }
    }
}

#Preview {
    DicePlayerRoot()
        .environment(DiceRootModel.preview)
}
