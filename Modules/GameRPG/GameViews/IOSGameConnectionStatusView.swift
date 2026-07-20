// @copyright André Trettin

#if os(iOS)
import SwiftUI

struct IOSGameConnectionStatusView: View {
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
    IOSGameConnectionStatusView(status: .sharePlayWaiting)
}
#endif
