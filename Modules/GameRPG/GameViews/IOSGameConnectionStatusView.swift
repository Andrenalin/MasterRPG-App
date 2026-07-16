// @copyright André Trettin

#if os(iOS)
import SwiftUI

struct IOSGameConnectionStatusView: View {
    let playerController: PlayerController

    var body: some View {
        Label {
            Text(
                playerController.gameModel.lostMaster ? "Connection Lost" : "Connected",
                bundle: .module
            )
        } icon: {
            Image(systemName: playerController.gameModel.lostMaster ? "wifi.slash" : "wifi")
        }
        .labelStyle(.iconOnly)
        .foregroundStyle(playerController.gameModel.lostMaster ? .red : .teal)
        .help(
            Text(
                playerController.gameModel.lostMaster ? "Connection Lost" : "Connected",
                bundle: .module
            )
        )
    }
}

#Preview {
    IOSGameConnectionStatusView(playerController: .preview)
}
#endif
