// @copyright André Trettin

import AndrenalinKit
import SwiftUI

public extension View {
    func environmentSetUp(_ appModel: AppStore) -> some View {
        modifier(AppEnvironmentSetUpViewModifier(appModel: appModel))
    }
}

struct AppEnvironmentSetUpViewModifier: ViewModifier {
    let appModel: AppStore
    
    func body(content: Content) -> some View {
        content
            .environment(appModel.deviceRotationModel)
            .environment(appModel.optionKeyDownModel)
            .environment(appModel.settingsModel)
            .environment(appModel.selectionSheetLinkModel)
            .environment(appModel.windowStateModel)
            .environment(appModel.adventureRoot)
            .environment(appModel.audioRoot)
            .environment(appModel.valueRoot)
            .environment(appModel.diceRoot)
//        #if !os(tvOS)
//            .environment(appModel.generatorRoot)
//        #endif
            .environment(appModel.mapRoot)
            .environment(appModel.pdfRoot)
            .environment(appModel.photoRoot)
            .environment(appModel.spaceRoot)
            .environment(appModel.tableRoot)
            .environment(appModel.weatherRoot)
//            .environment(appModel.linkRootController)
            .environment(appModel)
            .observeRotate(with: appModel.deviceRotationModel)
    }
}
