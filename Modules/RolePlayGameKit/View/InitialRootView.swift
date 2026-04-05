// @copyright André Trettin

import CoreRPG
import SwiftUI

public struct InitialRootView: View {
    public init() {}
    
    @Environment(AppModel.self) private var appModel

    public var body: some View {
        appModel.appNavigationModel.initialRouteType
            .onContinueUserActivity(UserActivity.bundleIdentifierType) { userActivity in
                handle(userActivity: userActivity)
            }
    }

    private func handle(userActivity: NSUserActivity) {
        // SIRI & Search
        let module = UserActivity.module(from: userActivity)
        guard module != .none, let itemId = UserActivity.itemId(from: userActivity) else { return }
        let childId = UserActivity.childId(from: userActivity)
        // this must be stored on NavigationModel and done as soon the database is loaded
        appModel.navigator.perform(route: KnownRoutes.route(module: module, itemId: itemId, entryId: childId))
    }
}

#Preview {
    InitialRootView()
        .frame(width: 400, height: 400)
}
