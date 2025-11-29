// @copyright André Trettin

import AndrenalinKit
import RolePlayGameKit
import SwiftUI

@main
struct MasterTVApp: App {
    @State private var appModel = AppModel()

    @UIApplicationDelegateAdaptor private var appDelegate: IosAppDelegate

    var body: some Scene {
        WindowGroup("Game", id: WindowIdentifier.game.rawValue) {
            InitialRootView(appModel: appModel, editorOnly: false)
        }
    }
}
