// @copyright André Trettin

import CoreRPG
import SwiftUI

struct GameConnectionStatusIndicatorView: View {
    let status: GameConnectionStatusPresentation

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        Label {
            Text(status.title, bundle: .module)
        } icon: {
            Image(systemName: status.systemImage)
        }
        .labelStyle(.iconOnly)
        .foregroundStyle(status.tint)
        .help(Text(status.title, bundle: .module))
        .accessibilityLabel(Text(status.title, bundle: .module))
    }
}

#Preview {
    HStack {
        GameConnectionStatusIndicatorView(status: .localNetworkConnected)
        GameConnectionStatusIndicatorView(status: .localNetworkLost)
        GameConnectionStatusIndicatorView(status: .sharePlayWaiting)
        GameConnectionStatusIndicatorView(status: .sharePlayConnected)
        GameConnectionStatusIndicatorView(status: .sharePlayLost)
    }
    .padding()
}
