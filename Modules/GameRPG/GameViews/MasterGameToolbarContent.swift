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

        ToolbarItem(placement: .automatic) {
            // iOS exposes this control in OverlayGameMenu. macOS uses the
            // native window toolbar, so keep the same in-place 2D/3D switch
            // available here instead of requiring a separate table window.
            GameTableWindowButton()
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
