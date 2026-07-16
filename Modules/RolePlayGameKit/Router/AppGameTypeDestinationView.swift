// @copyright André Trettin

import CoreRPG
import GameRPG
import SwiftUI

struct AppGameTypeDestinationView: View {
    let type: AppModeRouteType

    @Environment(AppModel.self) private var appModel

    var body: some View {
        Group {
            switch type {
            case .game:
                GameFactory.rootGameView(root: appModel.gameRoot)
            case .gameVisionSetup:
                AppNavigationRouteType.visionSplit
            case .gameSetup:
                GameSetupDestinationView()
            case .editor:
                TabRootView(appModel: appModel)
            }
        }
        .tint(.blue)
        .environmentActionSetUp(appModel)
        .appExitNotifications(handler: appModel.save)
    }
}

#Preview("Game setup mode") {
    AppGameTypeDestinationView(type: .gameSetup)
        .environment(AppModel())
}
