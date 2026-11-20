// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftUI

struct OverlayMasterTabBar: View {
    let root: GameRoot
    let adventureId: UUID

    @Environment(GameScreenModel.self) private var gameScreenModel

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        ZStack(alignment: .trailing) {
#if os(macOS) || os(visionOS)
            OnlyGameView(root: root, adventureId: adventureId)
#else
            GameSidebarSlotsLayout(layout: gameScreenModel.sidebarLayout, placement: gameScreenModel.sidebarPlacement) {
                TabGameView(root: root, adventureId: adventureId)
            } secondary: {
                TabSecondGameView(root: root)
#if os(iOS)
                // The side panel is how iOS presents the battle round. macOS has
                // its own window for it, and no other platform opens the panel,
                // so none of them carries the view.
                BattleRoundSideOverlay(root: root)
#endif
            }
#if os(iOS)
            .gameSidebarLayoutSync(isMaster: true)
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
    OverlayMasterTabBar(root: .previewFixture(), adventureId: GamePreviewData.adventureID)
        .environment(GameScreenModel())
        .environment(AppSettingsModel())
        .environment(AppWindowSizeModel())
}
