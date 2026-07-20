// @copyright André Trettin

#if os(iOS)
import AudioRPG
import CoreRPG
import MapRPG
import SwiftUI

struct IOSGameOverlayControlField: View {
    let root: GameRoot
    let playerController: PlayerController?
    let isMaster: Bool
    let spacing: CGFloat

    var body: some View {
        let battleModel = root.mapRoot.mapGameControllable.battleRoundModel
        let presentation = GameChromeStatusPresentation(
            isBattleRunning: battleModel.isRunning,
            battleRound: battleModel.roundCounter,
            lostMaster: playerController?.gameModel.lostMaster ?? false,
            sharePlayState: root.networkStore.sharePlayStore.connectionState
        )

        HStack(spacing: spacing) {
            root.audioRoot.viewController.toolbarVolumeButton(root: root.audioRoot)

            GameBattleRoundIndicatorView(
                indicator: presentation.battleRoundIndicator
            )

            if isMaster {
                ControlSharingView(alignment: .bottom, embeddedInGlass: true) {}
                    .zIndex(1)
            }

            if playerController != nil {
                IOSGameConnectionStatusView(status: presentation.connectionStatus)
            }
        }
        .buttonStyle(.plain)
        .imageScale(.large)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}

private struct GameBattleRoundIndicatorView: View {
    let indicator: GameBattleRoundIndicator

    var body: some View {
        Group {
            switch indicator {
            case .inactive:
                Text(verbatim: "-")
                    .accessibilityLabel(Text("No active battle", bundle: .module))

            case let .round(round):
                Text(round, format: .number)
                    .accessibilityLabel(Text("Round \(round)", bundle: .module))
            }
        }
        .font(.headline)
        .monospacedDigit()
        .frame(minWidth: 20)
        .allowsHitTesting(false)
    }
}

#Preview(traits: .mockData) {
    let root = GameRoot.previewFixture(game: .player)
    IOSGameOverlayControlField(
        root: root,
        playerController: PlayerController(root: root, asGameMaster: false),
        isMaster: false,
        spacing: 8
    )
}
#endif
