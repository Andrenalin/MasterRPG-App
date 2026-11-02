// @copyright André Trettin

import CoreRPG
import RolePlayGameKit
import SwiftUI

@main
struct MasterTVApp: App {
    /// The one app model, the same the scene and app delegates use. A second `AppModel()` here
    /// left `AppModel.shared` as a model graph whose database is never set up, so `RPG://` links
    /// and continued activities, which the scene delegate hands to it, waited forever.
    /// See CODE_AUDIT_21 §5.26.
    private let appModel = AppModel.shared

    @UIApplicationDelegateAdaptor private var appDelegate: IosAppDelegate

    init() {
        MasterRPGTips.configure()
    }

    var body: some Scene {
        WindowGroup("Game", id: SceneId.game.rawValue) {
            // The same navigation setup as the Game window of MasterRPGApp: without the root
            // navigator, `navigator.navigate(to:method: .sheet / .managedSheet)` (Game Statistics,
            // supporter options) has nothing that presents, and the buttons do nothing.
            appModel.appNavigationModel.initialRouteType
                .onNavigationRoute(WindowRouter(appModel: appModel, role: .game))
                .onNavigationOpenURL(RootURLHandler(appModel: appModel, role: .game))
                .navigationRoot(appModel.gameNavigator)
                .sceneTracker(for: SceneId.game)
                .environmentSetUp(appModel)
                .appSettingsSetUp(appModel)
        }
    }
}
