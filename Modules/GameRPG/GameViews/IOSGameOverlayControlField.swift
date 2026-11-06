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
        let _ = Self.printViewChangesOnlyInDebug()
        let battleModel = root.mapRoot.mapGameControllable.battleRoundModel
        let presentation = GameChromeStatusPresentation(
            isBattleRunning: battleModel.isRunning,
            battleRound: battleModel.roundCounter,
            lostMaster: playerController?.gameModel.lostMaster ?? false,
            sharePlayState: root.networkStore.sharePlayStore.connectionState,
            // `.lost` is set the instant the LAN connection drops and this
            // device starts its fallback listener, waiting for the master to
            // dial back in with the already-known passcode — a real,
            // in-progress recovery distinct from a connection that never
            // recovers. See CODE_AUDIT_Reconnect §8.1.
            isReconnecting: root.isLocalNetworkReconnecting
        )

        HStack(spacing: spacing) {
            root.audioRoot.viewController.toolbarVolumeButton(root: root.audioRoot)

            GameBattleRoundIndicatorView(
                indicator: presentation.battleRoundIndicator
            )

            if root.offersTablePlayers(isMaster: isMaster) {
                // The game master's players (also the per-player "send updates" switches the
                // share button had), or a player's companions.
                TablePlayersButton(root: root)
            }

            GameJoinCodeRevealButton(
                root: root,
                isMaster: isMaster,
                connectionStatus: (isMaster ? nil : playerController) != nil ? presentation.connectionStatus : root.hostingStatus(isMaster: isMaster)
            )

            BatteryView()
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
        let _ = Self.printViewChangesOnlyInDebug()
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
