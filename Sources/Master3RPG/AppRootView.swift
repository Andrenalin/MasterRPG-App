// @copyright André Trettin

import CoreRPG
import RolePlayGameKit

import PhotoRPG
import SpaceRPG

import SwiftUI
import SwiftData

struct AppRootView: View {

    @Environment(AppModel.self) private var appModel
    
    var body: some View {
        let _ = Self._printChanges()
        
        TabNavigation()
            .environment(\.colorScheme, .dark)
            .environment(\.navigator, appModel.navigator)
            .environment(appModel.deviceRotationModel)
            .environment(appModel.photoRoot)
            .environment(appModel.spaceRoot)
            .frame(minWidth: 375.0, minHeight: 600.0)
            .tint(Color.teal)
            .observeRotate(with: appModel.deviceRotationModel)
    }
}


#Preview {
    AppRootView()
        .modelContainer(for: [PhotoDataModel.self, PhotoEntryDataModel.self, SpaceDataModel.self, SpaceEntryDataModel.self], inMemory: true)
        .environment(AppModel())
}
