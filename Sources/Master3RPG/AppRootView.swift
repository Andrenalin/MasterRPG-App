// @copyright André Trettin

import CoreRPG
import RolePlayGameKit

import AudioRPG
import DiceRPG
import PdfRPG
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
            .environment(appModel.audioRoot)
            .environment(appModel.diceRoot)
            .environment(appModel.pdfRoot)
            .environment(appModel.photoRoot)
            .environment(appModel.spaceRoot)
            .frame(minWidth: 375.0, minHeight: 600.0)
            .tint(Color.teal)
            .observeRotate(with: appModel.deviceRotationModel)
    }
}

#Preview {
    AppRootView()
        .modelContainer(for: [TagDataModel.self, ItemDataModel.self], inMemory: true)
        .environment(AppModel())
}
