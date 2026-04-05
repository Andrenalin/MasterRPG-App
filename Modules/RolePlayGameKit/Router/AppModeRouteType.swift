// @copyright André Trettin

import CoreRPG
import GameRPG
import SwiftUI

public enum AppModeRouteType: Codable, Equatable, Hashable {
    case editor
    case game
    case gameSetup
    case gameRootSetup
}

extension AppModeRouteType: NavigationDestination {
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
                    .setWideMode()
            case .gameSetup:
                GameFactory.rootSetupView(root: appModel.gameRoot)
            case .gameRootSetup:
                GameFactory.rootSetupView(root: appModel.gameRoot)
            case .editor:
                TabRootView(appModel: appModel)
                    .navigationRoot(appModel.navigator)
            }
        }
        .accentColor(.blue)
        .tint(.blue)
        .environmentActionSetUp(appModel)
    }
}
