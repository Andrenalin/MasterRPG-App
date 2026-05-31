// @copyright André Trettin

import AdventureRPG
import CoreRPG
import GameRPG
import SwiftUI

extension AppModeRouteType: @retroactive NavigationDestination {
    public var body: some View {
        AppGameTypeDestinationView(type: self)
    }
}

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
                GameFactory.rootSetupView(root: appModel.gameRoot)
            case .editor:
                TabRootView(appModel: appModel)
            }
        }
        .tint(.blue)
        .environmentActionSetUp(appModel)
        .appExitNotifications(handler: appModel.adventureRoot.save)
    }
}
