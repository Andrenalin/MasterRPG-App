// @copyright André Trettin

import CoreRPG
import GameRPG
import SwiftUI

enum GameStatisticsRoute: Hashable, Codable {
    case dashboard
}

extension GameStatisticsRoute: NavigationDestination {
    var body: some View {
        GameStatisticsRouteDestinationView()
    }
}

private struct GameStatisticsRouteDestinationView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        GameFactory.statisticsView(root: appModel.gameRoot)
    }
}

struct GameSetupDestinationView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(AppWindowSizeModel.self) private var appWindowSizeModel
    @Environment(ScenesManager.self) private var scenesManager
    @Environment(\.navigator) private var navigator

    var body: some View {
        GameFactory.rootSetupView(
            root: appModel.gameRoot,
            openStatistics: openStatistics
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
}
