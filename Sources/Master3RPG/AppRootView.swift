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
            .environment(appModel.deviceRotationModel)
            .environment(appModel.settingsModel)
            .environment(appModel.adventureRoot)
            .environment(appModel.audioRoot)
            .environment(appModel.characterRoot)
            .environment(appModel.diceRoot)
            .environment(appModel.mapRoot)
            .environment(appModel.pdfRoot)
            .environment(appModel.photoRoot)
            .environment(appModel.spaceRoot)
            .environment(appModel.tableRoot)
            .environment(appModel.weatherRoot)
            .environment(appModel.linkRootController)
            .environment(appModel)
            .observeRotate(with: appModel.deviceRotationModel)
            .onContinueUserActivity(UserActivity.bundleIdentifierType) { userActivity in
                handle(userActivity: userActivity)
            }
            .navigationRoot(appModel.navigator)
    }
    
    private func handle(userActivity: NSUserActivity) {
        // SIRI & Search
        let module = UserActivity.module(from: userActivity)
        guard module != .none, let itemId = UserActivity.itemId(from: userActivity) else { return }
        let childId = UserActivity.childId(from: userActivity)
        //let command: String? = UserActivity.command(from: userActivity)
        let child = childId != nil ? "/\(childId?.uuidString ?? "")" : ""
        let url = URL(string: "\(URL.appScheme)://\(module.token)/0/\(itemId)\(child)")!
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
