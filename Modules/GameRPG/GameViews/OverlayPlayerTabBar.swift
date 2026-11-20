// @copyright André Trettin

import CoreRPG
import SwiftUI

struct OverlayPlayerTabBar: View {
    let root: GameRoot

    @Environment(GameScreenModel.self) private var gameScreenModel

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        ZStack(alignment: .trailing) {
#if os(macOS) || os(visionOS)
            OnlyPlayerGameView(root: root)
#elseif os(tvOS)
            if root.gameModel.gameType != .observer {
                TabPlayerGameView(root: root)
                TabSecondGameView(root: root, isPlayer: true)
            }
#else
            GameSidebarSlotsLayout(layout: .single, placement: gameScreenModel.sidebarPlacement) {
                TabPlayerGameView(root: root)
            } secondary: {
                TabSecondGameView(root: root, isPlayer: true)
            }
#if os(iOS)
            .gameSidebarLayoutSync(isMaster: false)
#endif
#endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
#if !os(macOS)
        .ignoresSafeArea()
#endif
    }
}

#Preview {
    OverlayPlayerTabBar(root: GameRoot.preview)
        .environment(GameScreenModel())
        .environment(AppSettingsModel())
        .environment(AppWindowSizeModel())
}
