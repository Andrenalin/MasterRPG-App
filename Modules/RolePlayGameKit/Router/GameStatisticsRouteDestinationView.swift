// @copyright André Trettin

import CoreRPG
import GameRPG
import SwiftUI

struct GameStatisticsRouteDestinationView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        GameFactory.statisticsView(root: appModel.gameRoot)
    }
}

#Preview("Game statistics dashboard") {
    GameStatisticsRouteDestinationView()
        .environment(AppModel())
}
