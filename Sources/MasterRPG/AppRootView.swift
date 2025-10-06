// @copyright André Trettin

import CoreRPG
import CoreExternalRPG
import RolePlayGameKit
import GameRPG

import SwiftUI
import SwiftData

struct AppRootView: View {
    let appModel: AppModel
    
    var body: some View {
        let _ = Self._printChanges()
        
        AppRootSizedView(appModel: appModel)
#if os(macOS)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .toolbar(removing: .title)
#endif
            .modifier(UserSettingsViewModifier(appModel: appModel))
            .setAppSizeMode()
    }
}

struct AppRootSizedView: View {
    let appModel: AppModel
    
    @Environment(\.appSizeMode) private var appSizeMode
    
    var body: some View {
        let _ = Self._printChanges()
        
        appModel.gameRoot.viewController.gameWindow(root: appModel.gameRoot) {
            layout
        }
        .environmentSetUp(appModel)
        .navigationRoot(appModel.navigator)
        .onContinueUserActivity(UserActivity.bundleIdentifierType) { userActivity in
            handle(userActivity: userActivity)
        }
        .onChange(of: appSizeMode) { oldValue, newValue in
            appModel.resetNavigation()
        }
    }
    
    private func handle(userActivity: NSUserActivity) {
        let module = UserActivity.module(from: userActivity)
        guard module != .none, let itemId = UserActivity.itemId(from: userActivity) else { return }
        let childId = UserActivity.childId(from: userActivity)
        appModel.navigator.perform(route: KnownRoutes.route(module: module, itemId: itemId, entryId: childId))
    }
    
    private var layout: AppRootType {
        valueFor(iOS: appSizeMode == .compact ? .tabbed : .split, macOS: .tabbedSplit, tvOS: .tabbed, visionOS: .split)
    }
}

#Preview {
    AppRootView(appModel: AppModel())
        .modelContainer(AppModel().modelContainer)
}
