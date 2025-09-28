// @copyright André Trettin

import SwiftUI
import CoreRPG

struct DicePlayerRoot: View {
    @Environment(DiceRootModel.self) private var root

    @State private var showPlayerDice = true

    var body: some View {
        VStack(alignment: .trailing) {
            Button {
                withAnimation { showPlayerDice.toggle()
                }
            } label: {
                Image(systemName: root.itemController.module.icon)
            }
            .buttonStyle(.borderedProminent)

            DicePlayer(filterout: root.gameController.gameModel.focusItemIds.first ?? UUID(), alignment: .trailing)
                .opacity(showPlayerDice ? 1 : 0)
                .offset(x: showPlayerDice ? 0 : -200)
        }
    }
}

#Preview(traits: .mockData) {
    DicePlayerRoot()
}
