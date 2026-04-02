// @copyright André Trettin

import CoreRPG
import SwiftUI
import MapRPG
import GameRPG
import CharacterRPG

public extension View {
    func environmentSetUp(_ appModel: AppModel) -> some View {
        modifier(AppEnvironmentSetUpViewModifier(appModel: appModel))
    }
    
    func environmentActionSetUp(_ appModel: AppModel) -> some View {
        modifier(AppActionEnvironmentSetUpViewModifier(appModel: appModel))
    }
}

struct AppEnvironmentSetUpViewModifier: ViewModifier {
    let appModel: AppModel

    func body(content: Content) -> some View {
        content
            // Core models
            .environment(appModel)
            .environment(appModel.optionKeyDownModel)
            .environment(appModel.settingsModel)
            .environment(appModel.windowStateModel)

            // Module roots
            .environment(appModel.adventureRoot)
            .environment(appModel.audioRoot)
            .environment(appModel.characterRoot)
            .environment(appModel.diceRoot)
#if !os(tvOS)
            .environment(appModel.generatorRoot)
#endif
            .environment(appModel.mapRoot)
            .environment(appModel.pdfRoot)
            .environment(appModel.photoRoot)
            .environment(appModel.spaceRoot)
            .environment(appModel.tableRoot)
            .environment(appModel.weatherRoot)
    }
}

struct AppActionEnvironmentSetUpViewModifier: ViewModifier {
    let appModel: AppModel

    func body(content: Content) -> some View {
        content
            .environment(\.gameModus, appModel.settingsModel.gameModus)
            .environment(\.mapActions, appModel.mapRoot.mapActions)
            .environment(\.routeActions, appModel.routeActions)
            .environment(\.showGameActions, appModel.settingsModel.showGameActions)
            .environment(\.valueActions, appModel.characterRoot.valueActions)
    }
}
