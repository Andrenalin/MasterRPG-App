// @copyright André Trettin

import AndrenalinKit
import SwiftUI

struct SearchProxyView: View {
    let root: GameRoot

    @State private var playerNetworkController: (any PlayerNetworkControllable)?
    
    var body: some View {
        ScrollView {
            VStack {
                GroupBoxTV(isCard: true, withoutGroup: true) {
                    VStack {
                        Text("Conntect as proxy to extent your game view. The proxy will be acting as the same player as it is connected to. It can be use as second screen and as a sceond audio source. That has the advantage to have a const volume for the music during the game. On a shareplay device the music get ducked by the facetime environment.", bundle: .module)
                            .lineLimit(10)
                    }
                } label: {
                    Label {
                        Text("Search a game as Proxy", bundle: .module)
                            .font(.headline)
                    } icon: {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .imageScale(.large)
                    }
                }
                if let playerNetworkController {
                    BrowserView(root: root, playerNetworkControllable: playerNetworkController)
                        .environment(\.browserMode, .proxy)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .task {
                playerNetworkController = await root.networkProxyStore.model.playerNetworkController
            }
        }
    }
}

#Preview {
    SearchProxyView(root: .preview)
}
