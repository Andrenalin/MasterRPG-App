// @copyright André Trettin

import CoreRPG
import MapRPG
import SwiftUI

/// Presents battle management in the same trailing slot as the Adventure and
/// Character game views. The full-window game surface remains a sibling, so
/// showing this panel never changes the map or RealityView layout proposal.
struct BattleRoundSideOverlay: View {
    let root: GameRoot

    @Environment(GameScreenModel.self) private var gameScreenModel
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        BattleRoundView(
            model: root.battleRoundModel,
            actions: BattleRoundActionFactory.actions(for: root) {
                withAnimation(accessibilityReduceMotion ? nil : .default) {
                    gameScreenModel.showsBattleRoundSidebar = false
                }
            }
        )
        .environment(root.mapRoot)
        .frame(
            maxWidth: gameScreenModel.sideBarWidth,
            maxHeight: .infinity,
            alignment: .trailing
        )
#if os(iOS)
        .ignoresSafeArea(.container, edges: .bottom)
        .clipShape(.rect(topLeadingRadius: 14, topTrailingRadius: 14))
#endif
#if !os(visionOS)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
#endif
        .offset(
            x: gameScreenModel.showsBattleRoundSidebar
                ? 0
                : gameScreenModel.sideBarWidth
        )
        .opacity(gameScreenModel.showsBattleRoundSidebar ? 1 : 0)
        .allowsHitTesting(gameScreenModel.showsBattleRoundSidebar)
        .accessibilityHidden(!gameScreenModel.showsBattleRoundSidebar)
        .shadow(radius: 8)
        .animation(
            accessibilityReduceMotion ? nil : .bouncy,
            value: gameScreenModel.showsBattleRoundSidebar
        )
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            guard gameScreenModel.showsBattleRoundSidebar else { return }
            gameScreenModel.updateInlineMainOverlayWidth(width)
        }
    }
}

private struct BattleRoundSideOverlayPreview: View {
    @State private var root: GameRoot
    @State private var screenModel: GameScreenModel
    @State private var scenesManager = ScenesManager()

    init() {
        let screenModel = GameScreenModel()
        screenModel.showsBattleRoundSidebar = true
        _root = State(initialValue: GameRoot.previewFixture())
        _screenModel = State(initialValue: screenModel)
    }

    var body: some View {
        BattleRoundSideOverlay(root: root)
            .environment(screenModel)
            .environment(scenesManager)
            .frame(width: 800, height: 700, alignment: .trailing)
    }
}

#Preview("Battle sidebar") {
    BattleRoundSideOverlayPreview()
}
