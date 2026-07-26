// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftUI

struct OverlayMasterTabBar: View {
    let root: GameRoot
    let adventureId: UUID

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        ZStack(alignment: .trailing) {
#if os(macOS) || os(visionOS)
            OnlyGameView(root: root, adventureId: adventureId)
#else
            TabGameView(root: root, adventureId: adventureId)
            TabSecondGameView(root: root)
#endif
            BattleRoundSideOverlay(root: root)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
#if !os(macOS)
        .ignoresSafeArea()
#endif
    }
}

#Preview {
    OverlayMasterTabBar(root: .previewFixture(), adventureId: GamePreviewData.adventureID)
        .environment(GameScreenModel())
}
