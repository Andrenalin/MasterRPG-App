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
                .groupActivityAssociation(.primary(SceneId.gameTable.rawValue))
                .sceneTracker(for: SceneId.gameTable)
                .environment(appModel.scenesManager)
        }
        .windowStyle(.volumetric)
        .defaultSize(width: 1.5, height: 0.5, depth: 2.5, in: .meters)
        .restorationBehaviorAll(.disabled)
        
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
        .restorationBehaviorAll(.disabled)

        ImmersiveSpace(id: SceneId.spaceViewer.rawValue, for: ItemSelection.self) { $selection in
            DataBaseAppStoreAvailable(appModel: appModel) { appModel in
                appModel.spaceRoot.viewController.spaceImmersionWindow(root: appModel.spaceRoot, id: selection?.itemId ?? UUID(), defaultSize: defaultSize)
                    .sceneTracker(for: SceneId.spaceViewer)
//                    .groupActivityAssociation(selection != nil ? .primary(SceneId.spaceViewer.rawValue) : nil)
                    .modifier(WindowViewerSetUpViewModifier(model: appModel, module: .space))
            }
            .environment(appModel.scenesManager)
        }
        .defaultWindowPlacementAll(.above(NetworkModules.adventure.linkWindowId, fallback: SceneId.game.rawValue))
        .defaultSize(defaultSize, in: .meters)
        .immersionStyle(selection: $immersionState, in: .mixed)
    }
}
#endif
