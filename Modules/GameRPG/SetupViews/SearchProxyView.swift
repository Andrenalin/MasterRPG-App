// @copyright André Trettin

import CoreRPG
import SwiftUI

struct SearchProxyView: View {
    let root: GameRoot

    var body: some View {
        ScrollView {
            LazyVStack {
                GroupBoxTV(isCard: true, withoutGroup: true) {
                    Text("Observe any hosted game in the local network, or connect as proxy to extend a player to a second screen and audio source.", bundle: .module)
                        .lineLimit(10)
                } label: {
                    Label {
                        Text("Find a game", bundle: .module)
                            .font(.headline)
                    } icon: {
                        Image(systemName: "magnifyingglass.circle.fill")
                            .imageScale(.large)
                    }
                }

                if let observerController = root.networkStore.model.playerStore {
                    ForEach(observerController.browserManager.games) { browser in
                        BrowserRowView(root: root, playerNetworkControllable: observerController, model: browser)
                            .environment(\.browserMode, .observer)
                    }
                }

                if let proxyController = root.networkProxyStore.model.playerStore {
                    ForEach(visibleProxyBrowsers(for: proxyController)) { browser in
                        BrowserRowView(root: root, playerNetworkControllable: proxyController, model: browser)
                            .environment(\.browserMode, .proxy)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .onAppear {
            root.networkStore.model.playerStore?.browserManager.start()
            root.networkProxyStore.model.playerStore?.browserManager.start()
        }
    }
}

private extension SearchProxyView {
    func visibleProxyBrowsers(for controller: any PlayerNetworkControllable) -> [BrowserGameModel] {
        let observerNames = Set(
            (root.networkStore.model.playerStore?.browserManager.games ?? [])
                .map { $0.deviceName }
        )
        return controller.browserManager.games.filter { !observerNames.contains($0.deviceName) }
    }
}

#Preview {
    SearchProxyView(root: .preview)
}
