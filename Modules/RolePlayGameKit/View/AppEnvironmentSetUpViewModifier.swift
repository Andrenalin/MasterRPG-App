// @copyright André Trettin

import CoreRPG
import SwiftUI

public extension View {
    func environmentSetUp(_ appModel: AppModel) -> some View {
        modifier(AppEnvironmentSetUpViewModifier(appModel: appModel))
    }
}

struct AppEnvironmentSetUpViewModifier: ViewModifier {
    let appModel: AppModel
    
    func body(content: Content) -> some View {
        content
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
    }
}

