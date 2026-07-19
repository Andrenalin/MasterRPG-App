// @copyright André Trettin

import CoreRPG
import SwiftUI

/// Battle Round belongs to the game window's inline sidebar. This button uses
/// the same appearance as module window controls while never opening a second
/// scene from inside a running game.
struct BattleRoundSidebarButton: View {
    @Environment(GameScreenModel.self) private var gameScreenModel
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        Button(action: toggleBattleRoundSidebar) {
            Label {
                Text("Battle Round", bundle: .module)
            } icon: {
                Image(systemName: "shield.lefthalf.filled")
            }
        }
        .labelStyle(.iconOnly)
        .imageScale(.large)
        .padding(8)
        .contentShape(.circle)
        .modifier(
            GameWindowButtonAppearance(
                tint: NetworkModules.game.tint,
                isWindowPresented: gameScreenModel.showsBattleRoundSidebar
            )
        )
        .help(Text("Battle Round", bundle: .module))
        .accessibilityValue(
            Text(
                gameScreenModel.showsBattleRoundSidebar
                    ? "Sidebar shown"
                    : "Sidebar hidden",
                bundle: .module
            )
        )
    }

    private func toggleBattleRoundSidebar() {
        withAnimation(accessibilityReduceMotion ? nil : .default) {
            gameScreenModel.toggleBattleRoundSidebar()
        }
    }
}

#Preview {
    BattleRoundSidebarButton()
        .environment(GameScreenModel())
}
