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
        if appWindowSizeModel.mode == .compact {
            navigator.navigate(to: GameStatisticsRoute.dashboard)
        } else {
            navigator.present(sheet: GameStatisticsRoute.dashboard, managed: true)
        }
#else
        navigator.navigate(to: GameStatisticsRoute.dashboard)
#endif
    }

    private func openSupporter() {
        navigator.navigate(to: SettingsRoute.supporter, method: .managedSheet)
    }
}

#Preview("Game setup") {
    let appModel = AppModel()

    GameSetupDestinationView()
        .environment(appModel)
        .environment(AppWindowSizeModel())
        .environment(appModel.scenesManager)
}
