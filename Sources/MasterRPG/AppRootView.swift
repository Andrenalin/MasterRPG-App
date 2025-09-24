//
//  AppRootView.swift
//  MasterRPG
//
//  Created by Andre Trettin on 24.09.25.
//


// @copyright André Trettin

import CoreRPG
import CoreExternalRPG
import RolePlayGameKit

import SwiftUI
import SwiftData

struct AppRootView: View {
    let appModel: AppModel
    
    @Environment(\.appSizeMode) private var appSizeMode
    
    var body: some View {
        let _ = Self._printChanges()
        
        layout
            .environmentSetUp(appModel)
            .onContinueUserActivity(UserActivity.bundleIdentifierType) { userActivity in
                handle(userActivity: userActivity)
            }
            .navigationRoot(appModel.navigator)
            .onChange(of: appSizeMode) { oldValue, newValue in
                appModel.resetNavigation()
            }
            .setAppSizeMode()
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
