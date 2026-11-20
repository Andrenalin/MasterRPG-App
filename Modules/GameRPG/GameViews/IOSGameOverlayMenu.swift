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
    @Environment(GameScreenModel.self) private var gameScreenModel
    @Environment(\.gameTopTrailingOcclusionWidth) private var topTrailingOcclusionWidth

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        let buttonSpacing = GameScreenModel.mapOverlaySpacing
        GlassEffectContainerAll {
            if appWindowSizeModel.mode == .regular {
                ZStack {
                    HStack(spacing: itemSpacing) {
                        IOSGameOverlayCloseButton()

                        if isMaster || root.gameModel.gameType != .observer {
                            IOSGameDiceToggleButtonField()
                        }
                        Spacer()
                        IOSGameSidebarMenu(
                            isMaster: isMaster,
                            allowsPrimaryView: allowsPrimaryView,
                            showsViewToggles: false,
                            showsLayoutOptions: isMaster
                        )
                        // An overlay, so the buttons do not change the measured menu height
                        // that positions the sidebar content and dice. They hang below the
                        // menu button and move with it.
                        .overlay(alignment: .bottom) {
                            IOSGameSidebarViewButtons(
                                isMaster: isMaster,
                                allowsPrimaryView: allowsPrimaryView
                            )
                            .alignmentGuide(.bottom) { $0[.top] - buttonSpacing }
                        }
                    }

                    IOSGameOverlayControlField(
                        root: root,
                        playerController: playerController,
                        isMaster: isMaster,
                        spacing: itemSpacing
                    )
                }
                .padding(.trailing, max(gameScreenModel.topMenuTrailingReservation, topTrailingOcclusionWidth))
            } else {
                HStack(spacing: itemSpacing) {
                    IOSGameOverlayCloseButton()

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
                        allowsPrimaryView: allowsPrimaryView,
                        showsPlacementOptions: true
                    )
                }
                .padding(.trailing, topTrailingOcclusionWidth)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var allowsPrimaryView: Bool {
        isMaster || root.gameModel.gameType != .observer
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
