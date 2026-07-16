// @copyright André Trettin

#if os(macOS)
import AudioRPG
import CoreRPG
import SwiftUI

enum GameToolbarRole: Equatable {
    case master
    case player
}

struct GameToolbarContent: ToolbarContent {
    let root: GameRoot
    let role: GameToolbarRole
    let playerController: PlayerController?

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            if role == .master || root.gameModel.gameType != .observer {
                GameDiceToggleButton()
            }

            GameElapsedTimerText(startDate: root.gameModel.startGameTime)
        }

        ToolbarItemGroup(placement: .principal) {
            root.audioRoot.viewController.toolbarVolumeButton(root: root.audioRoot)

            if let playerController {
                PlayerConnectionStatusView(playerController: playerController)
            }
        }

        if role == .master || root.gameModel.gameType != .observer {
            ToolbarItem(placement: .automatic) {
                GameSidebarToolbarMenu(role: role)
            }
        }

        ToolbarSpacer(.fixed, placement: .automatic)

        ToolbarItem(placement: .automatic) {
            GameQuitToolbarButton()
        }
    }
}
#endif
