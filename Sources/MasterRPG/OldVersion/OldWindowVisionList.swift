// @copyright André Trettin

#if os(visionOS)
import AndrenalinKit
import RPGDie
import RoleGameKit
import RPGPhotos
import RPGSpaces
import SwiftUI


struct OldWindowVisionList: Scene {
    let appModel: AppModel
    
    @State private var immersionState: any ImmersionStyle = .mixed

    var body: some Scene {
        let defaultSize = Size3D(width: 1.5, height: 1, depth: 0.4)

        WindowGroup(id: "SpaceVolume", for: UUID.self) { $id in
            if let id {
                DataBaseAppStoreAvailable(appModel: appModel) { appModel in
                    appModel.spaceRoot.viewController.spaceImmersionWindow(root: appModel.spaceRoot, id: id, defaultSize: defaultSize)
                }
            }
        }
        .windowStyle(.volumetric)
        .defaultSize(defaultSize, in: .meters)

        ImmersiveSpace(id: WindowIdentifier.spaceViewer.rawValue, for: ItemSelection.self) { $selection in
            DataBaseAppStoreAvailable(appModel: appModel) { appModel in
                appModel.spaceRoot.viewController.spaceImmersionWindow(root: appModel.spaceRoot, id: selection?.itemId ?? UUID(), defaultSize: defaultSize)
                    .environment(appModel.windowStateModel)
            }
            .handlesExternalEvents(preferring: [], allowing: [])
        }
        .defaultWindowPlacementAll( .above(NetworkModules.adventure.linkWindowId, fallback: WindowIdentifier.game.rawValue))
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
