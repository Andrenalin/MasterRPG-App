// @copyright André Trettin

#if os(iOS)
import CoreRPG
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

                    IOSGameOverlayControlField(
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
