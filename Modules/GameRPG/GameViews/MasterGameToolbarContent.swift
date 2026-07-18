// @copyright André Trettin

#if os(macOS)
import AudioRPG
import CoreRPG
import MapRPG
import SwiftUI

enum GameToolbarRole: Equatable {
    case master
    case player
}

struct GameToolbarContent: ToolbarContent {
    let root: GameRoot
    let role: GameToolbarRole
    let playerController: PlayerController?

    @Environment(ScenesManager.self) private var scenesManager

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            if role == .master || root.gameModel.gameType != .observer {
                GameDiceToggleButton()
            }

            if role == .master {
                GameElapsedTimerText(startDate: root.gameModel.startGameTime)
            }
        }

        ToolbarItemGroup(placement: .principal) {
            root.audioRoot.viewController.toolbarVolumeButton(root: root.audioRoot)

            if let playerController {
                PlayerConnectionStatusView(playerController: playerController)
            }
        }

        if root.mapRoot.mapGameControllable.battleRoundModel.isRunning {
            ToolbarItem(placement: .automatic) {
                if role == .master {
                    BattleRoundStatusButton(
                        model: root.mapRoot.mapGameControllable.battleRoundModel
                    ) {
                        scenesManager.openWindow(.battleRound)
                    }
                } else {
                    BattleRoundCounterView(
                        model: root.mapRoot.mapGameControllable.battleRoundModel,
                        style: .compact
                    )
                }
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
