// @copyright André Trettin

import AdventureRPG
import CoreRPG
import Foundation
import SwiftUI

struct OnlyGameView: View {
    let root: GameRoot
    let adventureId: UUID

    @Environment(GameScreenModel.self) private var gameScreenModel
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        NavigationStack {
            root.adventureRoot.viewController.gameView(
                root: root.adventureRoot,
                focusedIds: [adventureId]
            )
        }
        .frame(maxWidth: gameScreenModel.sideBarWidth, maxHeight: .infinity, alignment: .trailing)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
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

#Preview {
    OnlyGameView(root: .previewFixture(), adventureId: GamePreviewData.adventureID)
        .environment(GameScreenModel())
}
