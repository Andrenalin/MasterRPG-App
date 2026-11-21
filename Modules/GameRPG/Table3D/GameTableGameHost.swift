// @copyright André Trettin

#if os(visionOS)
import CoreRPG
import PhotoRPG
import SpaceRPG
import WeatherRPG
import SwiftUI

extension View {
    /// Makes the table window the host of the running game on visionOS, where the 2D game screen
    /// is not on screen anymore: it ends the game when the window closes or the game stops, opens
    /// the windows the game requests (spatial photo, weather, 3D object) and refreshes the
    /// hosting services when the app returns.
    func gameTableGameHost(root: GameRoot) -> some View {
        modifier(GameTableGameHostModifier(root: root))
    }
}

private struct GameTableGameHostModifier: ViewModifier {
    let root: GameRoot

    @Environment(ScenesManager.self) private var scenesManager
    @Environment(AppGameStateModel.self) private var appGameStateModel: AppGameStateModel?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    private var controller: GameTablePresentationController {
        GameTablePresentationController(root: root, scenesManager: scenesManager, appGameStateModel: appGameStateModel)
    }

    func body(content: Content) -> some View {
        let playerController = root.gameModel.playerController
        content
            .onAppear {
                // The start window that first handed the scene manager its window actions is
                // gone by now: take them from this window, which stays as long as the game.
                scenesManager.setActions(
                    openWindow: openWindow,
                    dismissWindow: dismissWindow,
                    openImmersiveSpace: openImmersiveSpace,
                    dismissImmersiveSpace: dismissImmersiveSpace
                )
            }
            // The game stopped without this window: the game master quit, or the connection ended.
            .onChange(of: root.gameModel.gameConfig.state) { _, state in
                guard state == .stopped else { return }
                let controller = controller
                Task { await controller.endGame() }
            }
            .onDisappear {
                controller.tableDidDisappear()
            }
            .onChange(of: scenePhase) { _, phase in
                // Hosting services can stop while the app is suspended; check them when it
                // returns. See CODE_AUDIT_Join §5.3.
                guard phase == .active else { return }
                root.applicationBecameActive()
            }
            // Follows the presented photo, not the photo module's `currentItemId`: only a
            // show-photo event sets it, so a photo a map merely stored never opens the viewer.
            .onChange(of: root.photoRoot.photoGameControllable.presentedPhotoId) { _, photoId in
                guard let photoId else { return }
                root.photoRoot.imagePresentationModel.selectedItemId = photoId
                scenesManager.openWindow(SceneId.imageSpaceViewer)
            }
            // A photo over the map that goes full screen: the presented photo may be the same as
            // before, so the switch itself opens the viewer.
            .onChange(of: playerController?.gameModel.mapPhoto.fullScreenRequest) {
                guard let mapPhoto = playerController?.gameModel.mapPhoto,
                      let presentation = mapPhoto.presentation,
                      presentation.module == .photo,
                      mapPhoto.mode == .fullScreen
                else { return }
                root.photoRoot.imagePresentationModel.selectedItemId = presentation.itemId
                scenesManager.openWindow(SceneId.imageSpaceViewer)
            }
            // A weather shown full screen also opens in the weather window: its photo in spatial
            // 3D with the weather in front of it.
            .onChange(of: playerController?.gameModel.weatherWindowRequest) {
                guard playerController?.gameModel.gameUpdateType == .weather,
                      let weatherId = root.weatherRoot.gameControllable.gameModel.currentItemId
                else { return }
                root.weatherRoot.showSpatialWeather(itemId: weatherId)
                scenesManager.openWindow(SceneId.weatherSpaceViewer)
            }
            // Goes straight to the immersive space: a 2D reveal panel would only host
            // SpaceQuickLook's near-invisible trigger button. Always opens, also while the table
            // is open: the table does not render the shared object itself.
            .onChange(of: root.spaceRoot.gameControllable.gameModel.currentItemId) {
                guard let spaceId = root.spaceRoot.gameControllable.gameModel.currentItemId else {
                    // The game master un-revealed the space entirely: clear an earlier explicit
                    // dismiss so a future re-reveal of the same item opens fresh.
                    scenesManager.clearExplicitlyDismissedSpaceItem()
                    return
                }
                // A player who explicitly closed this exact reveal (the space viewer's own close
                // button) must not have it popped back open by a resync that re-broadcasts it;
                // see `ScenesManager.explicitlyDismissedSpaceItemId`.
                guard scenesManager.explicitlyDismissedSpaceItemId != spaceId else { return }
                Task {
                    await scenesManager.showSpaceViewer(selection: ItemSelection(itemId: spaceId, entryId: nil))
                }
            }
    }
}
#endif
