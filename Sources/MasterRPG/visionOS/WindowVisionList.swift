// @copyright André Trettin

#if os(visionOS)
import CoreRPG
import DiceRPG
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

        WindowGroup(id: SceneId.imageSpaceViewer.rawValue) {
            appModel.photoRoot.viewController.imageSpaceView()
                .environmentSetUp(appModel)
                .frame(minWidth: 600, maxWidth: 2000, minHeight: 600, maxHeight: 2000)
        }
        .windowResizability(.contentSize)
        .windowStyle(.plain)

        WindowGroup(id: SceneId.gameTable.rawValue) {
            GameTableView().volumeBaseplateVisibility(.hidden)
        }
        .windowStyle(.volumetric)
        .defaultSize(width: 2, height: 1.5, depth: 2, in: .meters)

        Window("Settings", id: SceneId.settings.rawValue) {
            DataBaseAppStoreAvailable(appModel: appModel) { appModel in
                NavigationStack {
                    SettingsView(store: appModel)
                }
                .setAppSizeMode()
                .environmentSetUp(appModel)
                .frame(minWidth: 800, minHeight: 600)
            }
        }
        .windowResizability(.contentSize)
        .defaultWindowPlacementAll(.below(SceneId.game.rawValue))
        
        WindowGroup(id: "SpaceVolume", for: UUID.self) { $id in
            if let id {
                DataBaseAppStoreAvailable(appModel: appModel) { appModel in
                    appModel.spaceRoot.viewController.spaceImmersionWindow(root: appModel.spaceRoot, id: id, defaultSize: defaultSize)
                }
            }
        }
        .windowStyle(.volumetric)
        .defaultSize(defaultSize, in: .meters)

        ImmersiveSpace(id: SceneId.spaceViewer.rawValue, for: ItemSelection.self) { $selection in
            DataBaseAppStoreAvailable(appModel: appModel) { appModel in
                appModel.spaceRoot.viewController.spaceImmersionWindow(root: appModel.spaceRoot, id: selection?.itemId ?? UUID(), defaultSize: defaultSize)
                    .sceneTracker(for: SceneId.spaceViewer)
                    .groupActivityAssociation(selection != nil ? .primary(SceneId.spaceViewer.rawValue) : nil)
            }
        }
        .defaultWindowPlacementAll( .above(NetworkModules.adventure.linkWindowId, fallback: SceneId.game.rawValue))
        //.windowStyle(.volumetric)
        .defaultSize(defaultSize, in: .meters)
        .immersionStyle(selection: $immersionState, in: .mixed)

        ImmersiveSpace(id: "Space3d", for: UUID.self) { $id in
            if let id {
                DataBaseAppStoreAvailable(appModel: appModel) { appModel in
                    appModel.spaceRoot.viewController.spaceImmersionWindow(root: appModel.spaceRoot, id: id, defaultSize: defaultSize)
                }
            }
        }
        .immersionStyle(selection: $immersionState, in: .mixed)

        ImmersiveSpace(id: DiceSpace.immersiveSpaceId) {
            DataBaseAppStoreAvailable(appModel: appModel) { appModel in
                DiceSpace(root: appModel.diceRoot)
            }
        }
        .immersionStyle(selection: $immersionState, in: .mixed)

        // Defines an immersive space to present a destination in which to watch the video.
        ImmersiveSpace(id: "PhotoWorld", for: PhotoWorldSelection.self) { $photoSelection in
            if let photoSelection {
                DataBaseAppStoreAvailable(appModel: appModel) { appModel in
                    ImmersivePhotoView(root: appModel.photoRoot, photoSelection: photoSelection)
                }
            }
        }
        .immersionStyle(selection: .constant(.progressive), in: .progressive)
    }
}
#endif
