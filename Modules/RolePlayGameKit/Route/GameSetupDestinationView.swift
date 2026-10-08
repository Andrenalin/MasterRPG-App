// @copyright André Trettin

import CoreRPG
import GameRPG
import SwiftUI

struct GameSetupDestinationView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(AppWindowSizeModel.self) private var appWindowSizeModel
    @Environment(ScenesManager.self) private var scenesManager
    @Environment(\.navigator) private var navigator

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()

        GameFactory.rootSetupView(
            root: appModel.gameRoot,
            openStatistics: openStatistics,
            openSupporter: openSupporter
        )
    }

    private func openStatistics() {
#if os(macOS) || os(visionOS)
        scenesManager.openWindow(.gameStatistics)
#elseif os(iOS)
        navigator.navigate(to: GameStatisticsRoute.dashboard, method: .managedSheet)
#else
        navigator.navigate(to: GameStatisticsRoute.dashboard, method: .managedSheet)
#endif
    }

    private func openSupporter() {
        var method: NavigationMethod
        
#if os(macOS)
        method = .managedSheet
#else
        method = .sheet
#endif
        
        navigator.navigate(to: SettingsRoute.supporter, method: method)
    }
}

#Preview("Game setup") {
    let appModel = AppModel()

    GameSetupDestinationView()
        .environment(appModel)
        .environment(AppWindowSizeModel())
        .environment(appModel.scenesManager)
        .environment(AppGameStateModel())
}
