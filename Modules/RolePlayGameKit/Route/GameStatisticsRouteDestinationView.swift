// @copyright André Trettin

import CoreRPG
import GameRPG
import SwiftUI

struct GameStatisticsRouteDestinationView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(AppWindowSizeModel.self) private var appWindowSizeModel

    var body: some View {
        GameFactory.statisticsView(
            root: appModel.gameRoot,
            showsDismissButton: appWindowSizeModel.mode != .compact
        )
    }
}

#Preview("Game statistics dashboard") {
    GameStatisticsRouteDestinationView()
        .environment(AppModel())
        .environment(AppWindowSizeModel())
}
