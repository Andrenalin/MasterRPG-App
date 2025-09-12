// @copyright André Trettin

import CoreRPG
import RolePlayGameKit

import SwiftUI
import SwiftData

struct AppRootView: View {

    @Environment(AppModel.self) private var appModel
    
    var body: some View {
        let _ = Self._printChanges()
        
        TabNavigation()
            .environment(\.navigator, appModel.navigator)
            .environment(appModel.deviceRotationModel)
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
            .observeRotate(with: appModel.deviceRotationModel)
    }
}

#Preview {
    AppRootView()
        .modelContainer(for: [TagDataModel.self, ItemDataModel.self], inMemory: true)
        .environment(AppModel())
}
