// @copyright André Trettin

import SwiftUI

struct BrowserView: View {
    let root: GameRoot
    let playerNetworkControllable: any PlayerNetworkControllable

    var body: some View {
        VStack(spacing: 20) {
            if !playerNetworkControllable.browserController.model.browsers.isEmpty {
                Text(playerNetworkControllable.browserController.model.statusMessage, bundle: .module)
            }
            ForEach(playerNetworkControllable.browserController.model.browsers) { browser in
                BrowserRowView(root: root, playerNetworkControllable: playerNetworkControllable, model: browser)
            }
        }
        .onAppear {
            playerNetworkControllable.browserController.start()
        }
        .animation(.default, value: playerNetworkControllable.networkModel.isConnected)
        .animation(.default, value: playerNetworkControllable.browserController.isBrowsing)
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
