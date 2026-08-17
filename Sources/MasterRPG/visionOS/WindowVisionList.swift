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
        // Keep the system grab handle just outside the 70 cm tabletop instead
        // of at the front of the former 2.5 m-deep volume.
        .defaultSize(width: 0.85, height: 0.3, depth: 0.85, in: .meters)
        .defaultWindowPlacement { _, _ in
            // Place the game table in front of the user when opened
            WindowPlacement(.utilityPanel)
        }
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
