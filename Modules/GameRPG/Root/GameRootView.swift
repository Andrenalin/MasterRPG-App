// @copyright André Trettin

import CoreRPG
import SwiftUI

struct GameRootView: View {
    let root: GameRoot

    @Environment(AppSettingsModel.self) private var settingsModel
    @Environment(AppNavigationModel.self) private var appNavigationModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        gameView
            .environment(\.colorScheme, colorScheme)
            .onChange(of: root.gameModel.gameConfig.state, initial: true) {
                appNavigationModel.resetAppMode(isGame: root.gameModel.gameConfig.state == .started)
                if root.gameModel.gameConfig.state == .started {
                    settingsModel.gameModus = root.gameModel.gameConfig.isMaster ? .master : .player
                } else {
                    settingsModel.gameModus = .edit
                }
            }
    }

    var gameView: some View {
        Group {
            if let playerController = root.gameModel.playerController {
                if root.gameModel.gameConfig.type == .master {
                    MasterGameScreen(root: root, playerController: playerController, adventureId: root.gameModel.gameConfig.master.adventureId!)
                } else {
                    PlayerGameScreen(root: root, playerController: playerController)
                }
            }
        }
        .environment(\.networkActions, root.networkActions())
        .environment(\.sharingControlActions, root.sharingControlActions)
        .environment(\.sharingFeatureActions, root.sharingFeatureActions)

#if os(iOS)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
#endif
#if os(iOS) || os(visionOS)
        .toolbar(.hidden, for: .navigationBar)
#endif
    }
}

#Preview {
    GameRootView(root: .preview)
        .environment(AppSettingsModel())
}
