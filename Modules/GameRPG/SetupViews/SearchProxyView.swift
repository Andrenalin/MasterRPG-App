// @copyright André Trettin

import CoreRPG
import SwiftUI

struct SearchProxyView: View {
    let root: GameRoot
    private let startsServices: Bool

    init(root: GameRoot, startsServices: Bool = true) {
        self.root = root
        self.startsServices = startsServices
    }

    var body: some View {
        ScrollView {
            VStack {
                Text("Local Network", bundle: .module)
                    .bold()
                    .accessibilityAddTraits(.isHeader)

                if let statusController = root.networkStore.model.playerStore ?? root.networkProxyStore.model.playerStore {
                    BrowserStatusView(browserManager: statusController.browserManager)
                }

                if empty {
#if os(tvOS)
                    Button {
                        Task {
                            await root.startDemo(supporterTier: .gold)
                        }
                    } label: {
                        Label {
                            Text("Demo", bundle: .module)
                        } icon: {
                            Image(systemName: "play.rectangle")
                        }
                    }
#else
                    Text("No hosted games found", bundle: .module)
                        .bold()
                        .accessibilityAddTraits(.isHeader)
#endif
                }
                
                if let observerController = root.networkStore.model.playerStore {
                    ForEach(observerController.browserManager.games) { browser in
                        BrowserRowView(root: root, playerNetworkControllable: observerController, model: browser)
                            .equatable()
                            .environment(\.browserMode, .observer)
                    }
                }

                if let proxyController = root.networkProxyStore.model.playerStore {
                    ForEach(visibleProxyBrowsers(for: proxyController)) { browser in
                        BrowserRowView(root: root, playerNetworkControllable: proxyController, model: browser)
                            .equatable()
                            .environment(\.browserMode, .proxy)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .onAppear {
            guard startsServices else { return }
            root.networkStore.model.playerStore?.browserManager.start()
            root.networkProxyStore.model.playerStore?.browserManager.start()
        }
        .onDisappear {
            guard startsServices else { return }
            for controller in [root.networkStore.model.playerStore, root.networkProxyStore.model.playerStore] {
                guard let controller, controller.networkModel.playerConnectionId == nil else { continue }
                controller.browserManager.stop()
            }
        }
    }
    
    var empty: Bool {
        var isEmpty = true
        if let observerController = root.networkStore.model.playerStore {
            isEmpty = isEmpty && observerController.browserManager.games.isEmpty
        }
        if let proxyController = root.networkProxyStore.model.playerStore, isEmpty == true {
            isEmpty = isEmpty && visibleProxyBrowsers(for: proxyController).isEmpty
        }
        return isEmpty
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
    SearchProxyView(root: .preview, startsServices: false)
}
