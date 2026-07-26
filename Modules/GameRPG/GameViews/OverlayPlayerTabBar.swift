// @copyright André Trettin

import CoreRPG
import SwiftUI

struct OverlayPlayerTabBar: View {
    let root: GameRoot

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        ZStack(alignment: .trailing) {
#if os(macOS) || os(visionOS)
            OnlyPlayerGameView(root: root)
#elseif os(tvOS)
            if root.gameModel.gameType != .observer {
                TabPlayerGameView(root: root)
                TabPlayerSecondGameView(root: root)
            }
#else
            TabPlayerGameView(root: root)
            TabPlayerSecondGameView(root: root)
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
}
