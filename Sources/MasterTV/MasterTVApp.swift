// @copyright André Trettin

import CoreRPG
import RolePlayGameKit
import SwiftUI

@main
struct MasterTVApp: App {
    @State private var appModel = AppModel()

    @UIApplicationDelegateAdaptor private var appDelegate: IosAppDelegate

    var body: some Scene {
        WindowGroup("Game", id: SceneId.game.rawValue) {
            appModel.appNavigationModel.initialRouteType
                .environmentSetUp(appModel)
                .appSettingsSetUp(appModel)
        }
    }
}
