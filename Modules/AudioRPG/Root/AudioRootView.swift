// @copyright André Trettin

import CoreRPG
import SwiftUI

struct AudioRootView: View {
    @Environment(AudioRootModel.self) private var root
    @Environment(\.navigator) private var navigator

    var body: some View {
        ItemRootView(root: root.rootController)
            .overlay {
                ItemStateRestorationView<AudioRoute, AudioRootModel>(root: root, keyPrefix: "Audio")
            }
            .onNavigationReceive { (route: AudioRoute, navigator) in
                guard let itemId = route.detail() else { return .cancel }
                root.navigationModel.selectedItemId = itemId
                return .auto
            }
    }
}

#Preview(traits: .mockData) {
    ManagedNavigationStack {
        AudioRootView()
    }
}
