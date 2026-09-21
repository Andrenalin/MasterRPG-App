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
        sharePlayState: SharePlayConnectionState = .inactive,
        isReconnecting: Bool = false
    ) {
        status = GameConnectionStatusPresentation(
            lostMaster: playerController.gameModel.lostMaster,
            sharePlayState: sharePlayState,
            isReconnecting: isReconnecting
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
