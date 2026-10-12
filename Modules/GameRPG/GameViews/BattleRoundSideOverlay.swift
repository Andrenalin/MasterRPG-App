// @copyright André Trettin

import CoreRPG
import MapRPG
import SwiftUI

/// Presents battle management in the same trailing slot as the Adventure and
/// Character game views. The full-window game surface remains a sibling, so
/// showing this panel never changes the map or RealityView layout proposal.
///
/// The panel exists only while it is shown. Kept mounted and merely moved
/// off screen, the whole battle screen — navigation stack, cards, text
/// fields, glass buttons, drop targets — kept running invisibly inside the
/// game screen. The screen model is this view's state, so a pending choice
/// and the expanded settings survive hiding and showing the panel.
struct BattleRoundSideOverlay: View {
    init(root: GameRoot) {
        self.root = root
        // Lazy: the game screen re-evaluates often, and a plain
        // `State(wrappedValue:)` built a new screen model each time.
        _screenModel = CoreRPG.LazyState(
            wrappedValue: BattleRoundScreenModel(model: root.battleRoundController.model)
        )
    }

    let root: GameRoot

    @Environment(GameScreenModel.self) private var gameScreenModel
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @CoreRPG.LazyState private var screenModel: BattleRoundScreenModel

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        ZStack(alignment: .trailing) {
            if gameScreenModel.showsBattleRoundSidebar {
                BattleRoundSidePanel(root: root, screenModel: screenModel)
                    .transition(
                        accessibilityReduceMotion
                            ? .opacity
                            : .move(edge: .trailing).combined(with: .opacity)
                    )
            }
        }
        .animation(
            accessibilityReduceMotion ? nil : .bouncy,
            value: gameScreenModel.showsBattleRoundSidebar
        )
    }
}

/// The battle screen as a side panel: sized to the sidebar, on glass.
private struct BattleRoundSidePanel: View {
    let root: GameRoot
    let screenModel: BattleRoundScreenModel

    @Environment(GameScreenModel.self) private var gameScreenModel
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        BattleRoundView(controller: root.battleRoundController, screenModel: screenModel, isSidePanel: true)
            .environment(root.mapRoot)
            .onChange(of: root.battleRoundController.model.isRunning) { wasRunning, isRunning in
                guard screenModel.battleRunningDidChange(
                    wasRunning: wasRunning,
                    isRunning: isRunning
                ) else { return }
                withAnimation(accessibilityReduceMotion ? nil : .default) {
                    gameScreenModel.showsBattleRoundSidebar = false
                }
            }
            .gameSidePanelIgnoringTrailingSafeArea()
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
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
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
