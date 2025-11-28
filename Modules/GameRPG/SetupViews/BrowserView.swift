// @copyright André Trettin

import SwiftUI

struct BrowserView: View {
    let root: GameRoot
    let playerNetworkControllable: any PlayerNetworkControllable
    
    var body: some View {
        VStack(spacing: 20) {
            if playerNetworkControllable.browserController.model.hasMessage {
                Text("Looking for Games:", bundle: .module)
                
                if playerNetworkControllable.browserController.model.hasMessage {
                    Text(playerNetworkControllable.browserController.model.statusMessage, bundle: .module)
                }
            }
            ForEach(playerNetworkControllable.browserController.model.browsers) { browser in
                BrowserRowView(root: root, playerNetworkControllable: playerNetworkControllable, model: browser)
            }
        }
        .onAppear { playerNetworkControllable.browserController.start() }
        .animation(.default, value: playerNetworkControllable.networkModel.isConnected)
        .animation(.default, value: playerNetworkControllable.browserController.isBrowsing)
    }
}

enum BrowserMode {
    case observer
    case player
    case proxy
}

struct BrowserModeKey: EnvironmentKey {
    static let defaultValue: BrowserMode = .player
}

extension EnvironmentValues {
    var browserMode: BrowserMode {
        get { self[BrowserModeKey.self] }
        set { self[BrowserModeKey.self] = newValue }
    }
}

#Preview {
    BrowserView(root: .preview, playerNetworkControllable: PlayerNetworkController(name: "Test"))
}
