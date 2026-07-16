// @copyright André Trettin

#if os(iOS)
import AudioRPG
import CoreRPG
import SwiftUI

struct IOSGameOverlayControlField: View {
    let root: GameRoot
    let playerController: PlayerController?
    let isMaster: Bool
    let spacing: CGFloat

    var body: some View {
        HStack(spacing: spacing) {
            root.audioRoot.viewController.toolbarVolumeButton(root: root.audioRoot)

            if isMaster {
                ControlSharingView(alignment: .bottom, embeddedInGlass: true) {}
                    .zIndex(1)
            }

            if let playerController {
                IOSGameConnectionStatusView(playerController: playerController)
            }
        }
        .buttonStyle(.plain)
        .imageScale(.large)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .glassEffect(.regular.interactive(), in: .capsule)
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
