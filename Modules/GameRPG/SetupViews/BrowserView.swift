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

            BrowserStatusView(browserManager: playerNetworkControllable.browserManager)

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
            playerNetworkControllable.browserManager.screenAppeared()
        }
        .onDisappear {
            // Discovery only runs while a screen needs it, or a join is under way or connected.
            // See CODE_AUDIT_Join §7.2.
            guard startsServices else { return }
            playerNetworkControllable.browserManager.screenDisappeared(
                keepRunning: playerNetworkControllable.networkModel.playerConnectionId != nil
            )
        }
        .animation(accessibilityReduceMotion ? nil : .default, value: playerNetworkControllable.networkModel.isConnected)
        .animation(accessibilityReduceMotion ? nil : .default, value: playerNetworkControllable.browserManager.isBrowsing)
    }
}

/// Explains why no games are listed when discovery is not simply empty: denied Local Network
/// access can never work until the setting changes, and a failed browser is being restarted.
/// See CODE_AUDIT_Join §8.2.
struct BrowserStatusView: View {
    let browserManager: BrowserManager

    var body: some View {
        if browserManager.isLocalNetworkAccessDenied {
            Text("Local Network access is turned off for MasterRPG. Turn it on in Settings to find games.", bundle: .module)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        } else if browserManager.errorMessage != nil {
            Text("Searching for games was interrupted. Trying again…", bundle: .module)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
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
