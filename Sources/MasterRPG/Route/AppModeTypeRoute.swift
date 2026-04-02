// @copyright André Trettin

import CoreRPG
import GameRPG
import RolePlayGameKit
import SwiftUI

enum AppModeTypeRoute: Codable, Equatable, Hashable {
    case editor
    case game
    case gameSetup
}

extension AppModeTypeRoute: NavigationDestination {
    var body: some View {
        AppGameTypeDestinationView(type: self)
    }
}

struct AppGameTypeDestinationView: View {
    let type: AppModeTypeRoute
    
    @Environment(AppModel.self) private var appModel
    
    var body: some View {
        Group {
            switch type {
            case .game:
                GameFactory.rootGameView(root: appModel.gameRoot)
                    .setWideMode()
            case .gameSetup:
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
