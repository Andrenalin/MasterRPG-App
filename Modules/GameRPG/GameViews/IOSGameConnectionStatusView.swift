// @copyright André Trettin

import CoreRPG
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
        let _ = Self.printViewChangesOnlyInDebug()
        GameConnectionStatusIndicatorView(status: status)
    }
}

#Preview {
    IOSGameConnectionStatusView(status: .sharePlayWaiting)
}
#endif
