// @copyright André Trettin

import CoreRPG
import MapRPG
import SwiftUI

/// Presents battle management in the same trailing slot as the Adventure and
/// Character game views. The full-window game surface remains a sibling, so
/// showing this panel never changes the map or RealityView layout proposal.
struct BattleRoundSideOverlay: View {
    init(root: GameRoot) {
        self.root = root
        _screenModel = State(
            wrappedValue: BattleRoundScreenModel(model: root.battleRoundController.model, layout: .compact)
        )
    }

    let root: GameRoot

    @Environment(GameScreenModel.self) private var gameScreenModel
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var screenModel: BattleRoundScreenModel

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        BattleRoundView(controller: root.battleRoundController, screenModel: screenModel)
        .environment(root.mapRoot)
        .onChange(of: root.battleRoundController.model.isRunning) { wasRunning, isRunning in
            guard wasRunning, !isRunning else { return }
            withAnimation(accessibilityReduceMotion ? nil : .default) {
                gameScreenModel.showsBattleRoundSidebar = false
            }
        }
        .frame(
            maxWidth: gameScreenModel.sideBarWidth,
            maxHeight: .infinity,
            alignment: .trailing
        )
#if os(iOS)
        .ignoresSafeArea(.container, edges: .bottom)
        .glassEffect(in: .rect(topLeadingRadius: ResolvedAppTheme.panelCornerRadius, topTrailingRadius: ResolvedAppTheme.panelCornerRadius))
#elseif !os(visionOS)
        .glassEffect(in: .rect(cornerRadius: ResolvedAppTheme.panelCornerRadius))
#endif
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        .offset(
            x: gameScreenModel.showsBattleRoundSidebar
                ? 0
                : gameScreenModel.sideBarWidth
        )
        .opacity(gameScreenModel.showsBattleRoundSidebar ? 1 : 0)
        .allowsHitTesting(gameScreenModel.showsBattleRoundSidebar)
        .accessibilityHidden(!gameScreenModel.showsBattleRoundSidebar)
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

#Preview("Battle sidebar", traits: .mockData) {
    BattleRoundSideOverlayPreview()
        .environment(AppGameStateModel())
}
