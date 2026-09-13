// @copyright André Trettin

import SwiftUI

struct BrowserView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    let root: GameRoot
    let playerNetworkControllable: any PlayerNetworkControllable
    private let startsServices: Bool

    init(
        root: GameRoot,
        playerNetworkControllable: any PlayerNetworkControllable,
        startsServices: Bool = true
    ) {
        self.root = root
        self.playerNetworkControllable = playerNetworkControllable
        self.startsServices = startsServices
    }

    var body: some View {
        VStack {
            Text("Local Network", bundle: .module)
                .bold()
                .accessibilityAddTraits(.isHeader)

            if playerNetworkControllable.browserManager.games.isEmpty {
                Text("No hosted games found", bundle: .module)
                    .bold()
                    .accessibilityAddTraits(.isHeader)
                    .padding()
                
            } else {
                ForEach(playerNetworkControllable.browserManager.games) { browser in
                    BrowserRowView(root: root, playerNetworkControllable: playerNetworkControllable, model: browser)
                        .equatable()
                }
            }
        }
        .onAppear {
            guard startsServices else { return }
            playerNetworkControllable.browserManager.start()
        }
        .animation(accessibilityReduceMotion ? nil : .default, value: playerNetworkControllable.networkModel.isConnected)
        .animation(accessibilityReduceMotion ? nil : .default, value: playerNetworkControllable.browserManager.isBrowsing)
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
    BrowserView(
        root: .preview,
        playerNetworkControllable: PlayerNetworkController(name: "Test"),
        startsServices: false
    )
}
