// @copyright André Trettin

#if os(macOS)
import SwiftUI

struct PlayerConnectionStatusView: View {
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
    PlayerConnectionStatusView(playerController: .preview)
}
#endif
