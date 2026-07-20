// @copyright André Trettin

#if os(macOS)
import SwiftUI

struct PlayerConnectionStatusView: View {
    let status: GameConnectionStatusPresentation

    init(status: GameConnectionStatusPresentation) {
        self.status = status
    }

    init(
        playerController: PlayerController,
        sharePlayState: SharePlayConnectionState = .inactive
    ) {
        status = GameConnectionStatusPresentation(
            lostMaster: playerController.gameModel.lostMaster,
            sharePlayState: sharePlayState
        )
    }

    var body: some View {
        GameConnectionStatusIndicatorView(status: status)
    }
}

#Preview {
    PlayerConnectionStatusView(status: .sharePlayConnected)
}
#endif
