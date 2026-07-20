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

    var body: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            GameQuitToolbarButton()
        }

        if role == .master || root.gameModel.gameType != .observer {
            ToolbarSpacer(.fixed, placement: .navigation)

            ToolbarItem(placement: .navigation) {
                GameDiceToggleButton()
            }

            ToolbarSpacer(.fixed, placement: .navigation)
        }

        if role == .master {
            ToolbarItem(placement: .navigation) {
                GameElapsedTimerText(startDate: root.gameModel.startGameTime)
            }
        }

        ToolbarItemGroup(placement: .principal) {
            root.audioRoot.viewController.toolbarVolumeButton(root: root.audioRoot)

            if role == .master,
               root.mapRoot.mapGameControllable.battleRoundModel.isRunning {
                BattleRoundCounterView(
                    model: root.mapRoot.mapGameControllable.battleRoundModel,
                    style: .compact
                )
                .allowsHitTesting(false)
            }

            if role == .player {
                PlayerBattleRoundToolbarStatus(
                    model: root.mapRoot.mapGameControllable.battleRoundModel
                )
            }

            if let playerController {
                let connectionStatus = GameConnectionStatusPresentation(
                    lostMaster: playerController.gameModel.lostMaster,
                    sharePlayState: root.networkStore.sharePlayStore.connectionState
                )
                PlayerConnectionStatusView(status: connectionStatus)
            }
        }

        if role == .master || root.gameModel.gameType != .observer {
            ToolbarItem(placement: .automatic) {
                GameSidebarToolbarMenu(role: role)
            }
        }

        ToolbarItem(placement: .primaryAction) {
            GameWindowSearchField()
        }
    }
}

private struct PlayerBattleRoundToolbarStatus: View {
    let model: BattleRoundModel

    var body: some View {
        Group {
            if model.isRunning {
                Text(model.roundCounter, format: .number)
            } else {
                Text(verbatim: "-")
            }
        }
        .monospacedDigit()
        .help(accessibilityText)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: Text {
        if model.isRunning {
            Text("Round \(model.roundCounter)", bundle: .module)
        } else {
            Text("No active battle", bundle: .module)
        }
    }
}
#endif
