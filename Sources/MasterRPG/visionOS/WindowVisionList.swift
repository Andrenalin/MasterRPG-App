// @copyright André Trettin

#if os(visionOS)
import CoreRPG
import GameRPG
import RolePlayGameKit
import PhotoRPG
import SpaceRPG
import SwiftUI
import GroupActivities

struct WindowVisionList: Scene {
    let appModel: AppModel

    @State private var immersionState: any ImmersionStyle = .mixed

    var body: some Scene {
        let defaultSize = Size3D(width: 1.5, height: 1, depth: 0.4)

        WindowGroup(id: SceneId.gameTable.rawValue) {
            GameTableView(root: appModel.gameRoot)
                .volumeBaseplateVisibility(.hidden)
                .sceneTracker(for: SceneId.gameTable)
                .environment(appModel.scenesManager)
                .gameTableActivityAssociation(root: appModel.gameRoot, sceneId: SceneId.gameTable.rawValue)
                // GameTableToolbar's ornament reaches for GameToolBar (needs
                // AppWindowSizeModel + networkActions), GameTableWindowButton
                // (needs AppSettingsModel), and now the dice action bar's
                // DiceGameActionBar (needs AppGameStateModel) — the volumetric
                // scene otherwise never picks these up the way the app's other
                // (navigation-hosted) windows do via
                // AppEnvironmentSetUpViewModifier/GameRootView.
                .setAppSizeMode()
                .environment(\.networkActions, appModel.gameRoot.networkActions)
                .environment(appModel.settingsModel)
                .environment(appModel.appGameStateModel)
        }
        .windowStyle(.volumetric)
        // Keep the system grab handle right at the tabletop's own edge
        // instead of the ~0.3 m gap the former, tableLength-derived width
        // left. SwiftUI gives no way to draw or reposition that handle from
        // inside `GameTableView`'s own body — a volumetric window's
        // grab/resize chrome is owned by the system and only ever
        // influenced indirectly, through the scene's own declared size —
        // so the actual derivation (why this specific width/height/depth,
        // and how it tracks the table's own footprint) lives once, in
        // `GameTableView.volumeSize`'s own doc, next to the table geometry
        // (`GameMetrics`) it depends on, instead of duplicated here.
        // `GameRenderer.rootOffset` reads that same
        // `GameTableView.volumeSize`/`.frontClearance` to place the table
        // inside whatever this declares, so the two can't drift apart.
        .defaultSize(GameTableView.volumeSize, in: .meters)
        // No `.defaultWindowPlacement` override — this used to return
        // `WindowPlacement(.utilityPanel)`, but `.utilityPanel` is a small,
        // near-body tool-panel position (meant for a persistent toolbar
        // that hovers by your hand), not a placement for a 2 m+ room-scale
        // volume. Using it here put a volume sized for a whole tabletop
        // where the system expects a small panel to sit — opening right at/
        // inside the viewer. Omitting this modifier falls back to the
        // scene's own default placement/sizing behavior — the normal
        // "opens in front of you" behavior every other volumetric window in
        // this app already gets.
        //
        // Deliberately no `.frame(width:height:)`/`.frame(depth:)` +
        // `physicalMetrics` pin on the content, and no explicit
        // `.windowResizability` override, either — tried twice, both times
        // it collapsed the window to a tiny fraction of its declared depth
        // instead of the intended fixed size. `GameRenderer` no longer reads
        // live window bounds for depth at all (see its own doc), so this
        // scene doesn't need to fight the system's resizability derivation
        // to keep the table's depth placement stable.
        .restorationBehavior(.disabled)

        WindowGroup(id: SceneId.gameRecover.rawValue) {
            Text("Recover", bundle: .main)
                .environment(appModel.scenesManager)
        }
        .windowResizability(.contentSize)
        .windowStyle(.plain)
        .restorationBehavior(.disabled)


        WindowGroup(id: SceneId.imageSpaceViewer.rawValue) {
            DataBaseAppStoreAvailable(appModel: appModel) { appModel in
                appModel.photoRoot.viewController.imageSpaceView()
                    .sceneTracker(for: SceneId.imageSpaceViewer)
                    // No themed background: this window's content is a
                    // RealityView (ImagePresentationView) that owns its own
                    // compositing against passthrough. See
                    // WindowViewerSetUpViewModifier.appliesBackground's doc —
                    // theme.backgroundGradient behind it was showing through
                    // as a black gradient whenever the spatial photo didn't
                    // fully cover the window.
                    .modifier(WindowViewerSetUpViewModifier(model: appModel, module: .photo, appliesBackground: false))
            }
            .environment(appModel.scenesManager)
            .frame(minWidth: 600, maxWidth: 2000, minHeight: 600, maxHeight: 2000)
        }
        .windowResizability(.contentSize)
        .windowStyle(.plain)
        .restorationBehavior(.disabled)
        .defaultWindowPlacementAll(imageSpaceViewerPlacement)

        ImmersiveSpace(id: SceneId.spaceViewer.rawValue, for: ItemSelection.self) { $selection in
            DataBaseAppStoreAvailable(appModel: appModel) { appModel in
                appModel.spaceRoot.viewController.spaceImmersionWindow(
                    root: appModel.spaceRoot,
                    // `currentSpaceViewerItemId` first: it's what `openSpaceViewer`
                    // updates to *replace* the shown item while already open — see
                    // its doc comment for why `selection` alone can't do that.
                    // `gameControllable.gameModel.currentItemId`/`selection` stay
                    // as fallbacks for paths that haven't gone through it yet.
                    id: appModel.scenesManager.currentSpaceViewerItemId
                        ?? appModel.spaceRoot.gameControllable.gameModel.currentItemId
                        ?? selection?.itemId
                        ?? Self.noSpaceSelectionId,
                    defaultSize: defaultSize
                )
                    .sceneTracker(for: SceneId.spaceViewer)
                    .modifier(WindowViewerSetUpViewModifier(model: appModel, module: .space, isImmersiveSpace: true))
            }
            .environment(appModel.scenesManager)
        }
        .defaultSize(defaultSize, in: .meters)
        .immersionStyle(selection: $immersionState, in: .mixed)
        .upperLimbVisibility(.hidden)
    }

    /// A stable "no selection" sentinel for the space viewer's `id:` — a freshly-minted random
    /// `UUID()` here churned view identity on every body re-evaluation that hit this fallback.
    /// See CODE_AUDIT §8.6.
    private static let noSpaceSelectionId = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    /// Stacks the spatial photo presentation window above the main "Game"
    /// window (`SceneId.game`) whenever a game is running.
    ///
    /// Deliberately does NOT anchor against the volumetric table window
    /// (`SceneId.gameTable`), even though it's open at exactly the times
    /// `SceneId.game` is pushed aside (see
    /// `GameTableWindowButton.toggleTable()`): returning
    /// `WindowPlacement(.above(volumetricWindowProxy))` for a `.volumetric`
    /// window reproducibly kept this window from opening at all, instead of
    /// falling back to a default placement the way the graceful "id not
    /// found" path in `WindowPlacementPosition.above(id:fallback:)` does.
    /// `SceneId.game`'s own `WindowProxy` keeps resolving even while it's
    /// backgrounded (pushed aside, not dismissed), so anchoring to it alone
    /// reopens reliably whether the table is showing or not; if it's ever
    /// not found either, `WindowPlacementPosition`'s existing "not found →
    /// no placement" fallback still applies, so this can't fail to open the
    /// window even then.
    ///
    /// Only applied while a game is actually running
    /// (`AppGameStateModel.isGameRunning`); a photo window opened for some
    /// other reason before/after a game falls back to the window's normal
    /// default placement (system-chosen), same as any other unconfigured
    /// window.
    ///
    /// visionOS's `WindowPlacement.Position` only offers this kind of
    /// semantic relative position (`.above`/`.below`/`.leading`/`.trailing`),
    /// with a system-chosen gap — there's no public API for an exact
    /// numeric offset (e.g. a fixed 50 cm) from another window, volumetric
    /// or not.
    private var imageSpaceViewerPlacement: WindowPlacementPosition {
        guard appModel.appGameStateModel.isGameRunning else { return .none }
        return .above(SceneId.game.rawValue)
    }
}
#endif
