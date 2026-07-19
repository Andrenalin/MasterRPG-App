// @copyright André Trettin

#if os(iOS)
import CoreRPG
import MapRPG
import SwiftUI

struct IOSGameOverlayMenu: View {
    let root: GameRoot
    let playerController: PlayerController?
    let isMaster: Bool

    @Environment(AppWindowSizeModel.self) private var appWindowSizeModel

    var body: some View {
        GlassEffectContainerAll {
            if appWindowSizeModel.mode == .regular {
                ZStack {
                    HStack(spacing: itemSpacing) {
                        if isMaster || root.gameModel.gameType != .observer {
                            IOSGameDiceToggleButtonField()
                        }
                        if isMaster {
                            IOSGameElapsedTimerText(startDate: root.gameModel.startGameTime)
                        }
                        Spacer()
                        IOSGameSidebarMenu(
                            isMaster: isMaster,
                            allowsPrimaryView: isMaster || root.gameModel.gameType != .observer
                        )
                        IOSGameOverlayCloseButton()
                    }

                    IOSGameOverlayCenterField(
                        root: root,
                        playerController: playerController,
                        isMaster: isMaster,
                        spacing: itemSpacing
                    )
                }
            } else {
                HStack(spacing: itemSpacing) {
                    if isMaster || root.gameModel.gameType != .observer {
                        IOSGameDiceToggleButtonField()
                        IOSGameSearchField()
                    }
                    Spacer(minLength: 0)
                    IOSGameOverlayControlField(
                        root: root,
                        playerController: playerController,
                        isMaster: isMaster,
                        spacing: itemSpacing
                    )
                    IOSGameSidebarMenu(
                        isMaster: isMaster,
                        allowsPrimaryView: isMaster || root.gameModel.gameType != .observer
                    )
                    IOSGameOverlayCloseButton()
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var itemSpacing: CGFloat {
        appWindowSizeModel.mode == .compact ? 4 : 8
    }
}

private struct IOSGameOverlayCenterField: View {
    let root: GameRoot
    let playerController: PlayerController?
    let isMaster: Bool
    let spacing: CGFloat

    @Environment(GameScreenModel.self) private var gameScreenModel

    var body: some View {
        let battleModel = root.mapRoot.mapGameControllable.battleRoundModel

        HStack(spacing: spacing) {
            if isMaster || root.gameModel.gameType != .observer {
                IOSGameSearchField()
            }

            if battleModel.isRunning && !gameScreenModel.showsBattleRoundAnnouncement {
                BattleRoundCounterView(model: battleModel, style: .compact)
                    .allowsHitTesting(false)
            }

            IOSGameOverlayControlField(
                root: root,
                playerController: playerController,
                isMaster: isMaster,
                spacing: spacing
            )
        }
    }
}

#Preview(traits: .mockData) {
    let root = GameRoot.previewFixture(game: .player)
    IOSGameOverlayMenu(
        root: root,
        playerController: PlayerController(root: root, asGameMaster: false),
        isMaster: false
    )
    .environment(GameScreenModel())
}
#endif
