// @copyright André Trettin

import CoreRPG
import SwiftUI
import MapRPG
import CharacterRPG

struct GameRootView: View {
    let root: GameRoot

    @Environment(AppGameStateModel.self) private var appGameStateModel

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()

        GameView(root: root)
            .onChange(of: root.gameModel.gameConfig.state, initial: true) { _, newState in
                let isRunning = newState == .started
                if appGameStateModel.isGameRunning != isRunning {
                    appGameStateModel.isGameRunning = isRunning
                }
                let newModus: GameModus = isRunning
                    ? (root.gameModel.gameConfig.isMaster ? .master : .player)
                    : .edit
                if appGameStateModel.gameModus != newModus {
                    appGameStateModel.gameModus = newModus
                }
            }
    }
}

private struct GameView: View {
    let root: GameRoot

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        Group {
            if let playerController = root.gameModel.playerController {
                if root.gameModel.gameConfig.isMaster {
                    if let adventureId = root.gameModel.gameConfig.master.adventureId {
                        MasterGameScreen(root: root, playerController: playerController, adventureId: adventureId)
                    }
                } else {
                    PlayerGameScreen(root: root, playerController: playerController)
                }
            }
        }
        .modifier(GameActionEnvironmentSetUpViewModifier(root: root))

#if os(iOS)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .modifier(GameHorizontalBarsModifier())
#endif
#if os(iOS) || os(visionOS)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
#endif
    }
}

#if os(iOS)
/// The game screen is a full-screen surface with its own chrome, so it opts out of the
/// trailing vertical bar (iPhone Duo): bar content such as the side panel's search field
/// falls back to the horizontal bars and the vertical bar's safe-area inset goes away.
private struct GameHorizontalBarsModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content
                .modifier(GameReclaimedTopModifier())
                .toolbarVerticalBehavior(.disabled)
        } else {
            content
        }
    }
}

/// Without the vertical bar the system reserves a top band for the status bar, which the
/// game hides. Where that band only exists because of a camera block in the top trailing
/// corner, the game uses it and tells the top menu how wide the corner is.
@available(iOS 27.1, *)
private struct GameReclaimedTopModifier: ViewModifier {
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var cornerWidth: CGFloat = 0

    func body(content: Content) -> some View {
        let isLeftToRight = layoutDirection == .leftToRight
        content
            .environment(\.gameTopTrailingOcclusionWidth, cornerWidth)
            .ignoresSafeArea(.container, edges: cornerWidth > 0 ? .top : [])
            // Measured outside the modifier above, so the result doesn't feed back into it.
            .onGeometryChange(for: CGFloat.self) { proxy in
                // The corner is a physical screen corner; only the left-to-right top menu
                // ends there.
                guard isLeftToRight else { return 0 }
                let frame = proxy.frame(in: .global)
                let insets = proxy.safeAreaInsets
                return GameTopOcclusion.reclaimableCornerWidth(
                    topInset: insets.top,
                    screenWidth: frame.maxX + insets.trailing,
                    occlusions: proxy.reservedRegions(kind: .occlusion, layoutDirectionBehavior: .fixed).map {
                        $0.frame.offsetBy(dx: frame.minX, dy: frame.minY)
                    }
                )
            } action: { width in
                cornerWidth = width
            }
    }
}
#endif

struct GameActionEnvironmentSetUpViewModifier: ViewModifier {
    let root: GameRoot

    func body(content: Content) -> some View {
        content
            .environment(\.mapActions, root.mapRoot.mapActions)
            .environment(\.networkActions, root.networkActions)
            .environment(\.isGamePlayer, root.isGamePlayer)
            .environment(\.quickDiceSlots, root.quickDiceSlots)
            .environment(\.sharingControlActions, root.sharingControlActions)
            .environment(\.sharingFeatureActions, root.sharingFeatureActions)
            .environment(
                \.itemGenerationResultAction,
                ItemGenerationResultAction(id: .object(ObjectIdentifier(root))) { summary in
                    root.gameModel.generatedValueEntry = ValueEntryModel(
                        generationSummary: summary
                    )
                }
            )
    }
}


#Preview(traits: .mockData) {
    GameRootView(root: .preview)
        .environment(AppFocusModel())
}
