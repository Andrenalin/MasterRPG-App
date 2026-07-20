// @copyright André Trettin

import SwiftUI

struct GameConnectionStatusIndicatorView: View {
    let status: GameConnectionStatusPresentation

    var body: some View {
        Label {
            Text(title, bundle: .module)
        } icon: {
            Image(systemName: systemImage)
        }
        .labelStyle(.iconOnly)
        .foregroundStyle(tint)
        .help(Text(title, bundle: .module))
        .accessibilityLabel(Text(title, bundle: .module))
    }

    private var title: LocalizedStringKey {
        switch status {
        case .localNetworkConnected, .sharePlayConnected:
            "Connected"
        case .localNetworkLost, .sharePlayLost:
            "Connection Lost"
        case .sharePlayWaiting:
            "Waiting for SharePlay"
        }
    }

    private var systemImage: String {
        switch status {
        case .localNetworkConnected:
            "wifi"
        case .localNetworkLost:
            "wifi.slash"
        case .sharePlayWaiting, .sharePlayConnected:
            "shareplay"
        case .sharePlayLost:
            "shareplay.slash"
        }
    }

    private var tint: Color {
        switch status {
        case .localNetworkConnected, .sharePlayConnected:
            .teal
        case .sharePlayWaiting:
            .orange
        case .localNetworkLost, .sharePlayLost:
            .red
        }
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
