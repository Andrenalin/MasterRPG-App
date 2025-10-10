// @copyright André Trettin

import AndrenalinKit
import RoleGameKit
import SwiftUI

@main
struct MasterTVApp: App {
    @State private var appStore = AppStore()

    @UIApplicationDelegateAdaptor private var appDelegate: IosAppDelegate

    var body: some Scene {
        WindowGroup("Game", id: WindowIdentifier.game.rawValue) {
            InitialRootView(appStore: appStore, editorOnly: false)
        }
    }
}
