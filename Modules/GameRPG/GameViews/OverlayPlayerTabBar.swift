// @copyright André Trettin

import SwiftUI

struct OverlayPlayerTabBar: View {
    let root: GameRoot

    var body: some View {
        ZStack(alignment: .trailing) {
#if os(macOS) || os(visionOS)
            OnlyPlayerGameView(root: root)
#else
            TabPlayerGameView(root: root)
            TabPlayerSecondGameView(root: root)
#endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
    }
}

#Preview {
    OverlayPlayerTabBar(root: GameRoot.preview)
        .environment(GameScreenModel())
}
