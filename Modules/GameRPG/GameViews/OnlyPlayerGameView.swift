// @copyright André Trettin

import CharacterRPG
import CoreRPG
import SwiftUI

struct OnlyPlayerGameView: View {
    let root: GameRoot

    @Environment(GameScreenModel.self) private var gameScreenModel
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        if root.gameModel.gameType != .observer {
            NavigationStack {
                root.characterRoot.viewController.gameView(
                    root: root.characterRoot,
                    select: root.gameModel.selectedCharacter
                )
            }
            .frame(maxWidth: gameScreenModel.sideBarWidth, maxHeight: .infinity, alignment: .trailing)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: ResolvedAppTheme.panelCornerRadius))
            .padding(.bottom, gameScreenModel.quickDiceBottomReservation)
            .offset(x: gameScreenModel.showMainTab == .none ? gameScreenModel.sideBarWidth : 0)
            .opacity(gameScreenModel.showMainTab == .none ? 0 : 1)
            .allowsHitTesting(gameScreenModel.showMainTab != .none)
            .accessibilityHidden(gameScreenModel.showMainTab == .none)
            .shadow(radius: 8)
            .animation(accessibilityReduceMotion ? nil : .bouncy, value: gameScreenModel.showMainTab)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                gameScreenModel.updateInlineMainOverlayWidth(width)
            }
        }
    }
}

#Preview {
    OnlyPlayerGameView(root: .previewFixture(game: .player))
        .environment(GameScreenModel())
}
