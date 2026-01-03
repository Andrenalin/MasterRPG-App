// @copyright André Trettin

import CoreRPG
import SwiftUI

struct GameRootView<Content: View>: View {
    let root: GameRoot
    let rootView: () -> Content

    @Environment(\.wideMode) private var wideMode
    @Environment(AppSettingsModel.self) private var settingsModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if root.gameModel.gameConfig.state == .started {
                gameView
                    .environment(\.colorScheme, colorScheme)
            } else {
#if os(macOS)
                GameRootTabItemView(root: root)
#else
                rootView()
#endif
            }
        }
        .onChange(of: root.gameModel.gameConfig.state, initial: true) {
            settingsModel.showGame <=> root.gameModel.gameConfig.state == .started
            if root.gameModel.gameConfig.state == .started {
                settingsModel.gameModus = root.gameModel.gameConfig.isMaster ? .master : .player
            } else {
                settingsModel.gameModus = .edit
            }
        }
    }

    var gameView: some View {
        Group {
            if root.gameModel.gameConfig.type == .master {
                MasterGameScreen(root: root, playerController: root.gameModel.playerController!, adventureId: root.gameModel.gameConfig.master.adventureId!)
            } else {
                PlayerGameScreen(root: root, playerController: root.gameModel.playerController!)
            }
        }
        .environment(\.networkActions, root.networkActions())
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
    GameRootView(root: .preview) {
        Text("Root View")
    }
    .environment(\.wideMode, .small)
    .environment(AppSettingsModel())
}
