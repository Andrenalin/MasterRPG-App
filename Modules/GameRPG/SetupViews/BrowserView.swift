// @copyright André Trettin

import SwiftUI

struct BrowserView: View {
    let root: GameRoot
    let playerNetworkControllable: any PlayerNetworkControllable

    var body: some View {
        VStack(spacing: 20) {
            if !playerNetworkControllable.browserManager.games.isEmpty {
                Text("Found \(playerNetworkControllable.browserManager.games.count) Players", bundle: .module)
            }
            ForEach(playerNetworkControllable.browserManager.games) { browser in
                BrowserRowView(root: root, playerNetworkControllable: playerNetworkControllable, model: browser)
            }
        }
        .onAppear {
            playerNetworkControllable.browserManager.start()
        }
        .animation(.default, value: playerNetworkControllable.networkModel.isConnected)
        .animation(.default, value: playerNetworkControllable.browserManager.isBrowsing)
    }
}

enum BrowserMode {
    case observer
    case player
    case proxy
}

extension EnvironmentValues {
    @Entry var browserMode: BrowserMode = .player
}

#Preview {
    BrowserView(root: .preview, playerNetworkControllable: PlayerNetworkController(name: "Test"))
}
