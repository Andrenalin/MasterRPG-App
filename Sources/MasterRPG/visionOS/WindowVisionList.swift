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
        // Keep the system grab handle just outside the tabletop instead of
        // at the front of the former 2.5 m-deep volume. Sized to
        // `GameMetrics.tableLength`/`tableWidth` (2.0 m × 1.5 m) plus the
        // same ~0.15 m clearance the original square 0.7 m table used —
        // RealityView clips content outside the volume's actual bounds
        // (see `GameTableView`), so this has to grow in lockstep with the
        // table itself, not just the table's own mesh/seat math.
        // Depth carries an extra 0.5 m of empty space in front of the table
        // beyond that clearance — `GameRenderer.placeTable(bottomY:)` pushes
        // the table back into it (using this same 2.15 m depth, duplicated
        // there as `GameRenderer.volumeDepth` since it can't reach this
        // constant directly) so the table doesn't sit right at the volume's
        // near bound, uncomfortably close to the viewer, when this window
        // opens.
        //
        // Height is 1.5 m — matching Apple's own TabletopKit samples that
        // include dice/toss physics (e.g. `.defaultSize(width: 1.5, height: 1.5,
        // depth: 1.5, in: .meters)`), not the table's own ~0.03 m thickness. A
        // tossed die's return-to-place animation arcs upward before settling;
        // this used to be only 0.3 m, tall enough for the static table itself
        // but not for that arc, and the die would clip through the volume's
        // ceiling mid-animation and vanish. `GameRenderer.placeTable(bottomY:)`
        // still keeps the table itself sitting on the real floor regardless of
        // how much headroom is declared above it, so this doesn't move the
        // table — it only gives tossed dice room to arc without leaving the
        // volume.
        .defaultSize(width: 2.15, height: 1.5, depth: 2.15, in: .meters)
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
            Text("Recover")
                .environment(appModel.scenesManager)
        }
        .windowResizability(.contentSize)
        .windowStyle(.plain)
        .restorationBehavior(.disabled)


        WindowGroup(id: SceneId.imageSpaceViewer.rawValue) {
            DataBaseAppStoreAvailable(appModel: appModel) { appModel in
                appModel.photoRoot.viewController.imageSpaceView()
                    .sceneTracker(for: SceneId.imageSpaceViewer)
                    .modifier(WindowViewerSetUpViewModifier(model: appModel, module: .photo))
            }
            .environment(appModel.scenesManager)
            .frame(minWidth: 600, maxWidth: 2000, minHeight: 600, maxHeight: 2000)
        }
        .windowResizability(.contentSize)
        .windowStyle(.plain)
        .restorationBehavior(.disabled)

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
}
#endif
