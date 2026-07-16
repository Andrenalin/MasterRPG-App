// @copyright André Trettin

import CoreRPG
import SwiftUI

struct SpaceRootView: View {
    @Environment(SpaceRootModel.self) private var root
    @Environment(\.navigator) private var navigator
    private let restoresState: Bool

    init(restoresState: Bool = true) {
        self.restoresState = restoresState
    }

    var body: some View {
        ItemRootView(root: root.rootController)
            .overlay {
                if restoresState {
                    ItemStateRestorationView<SpaceRoute, SpaceRootModel>(root: root, keyPrefix: "Space")
                }
            }
            .onNavigationReceive { (route: SpaceRoute, navigator) in
                guard let itemId = route.detail() else { return .cancel }
                root.navigationModel.selectedItemId = itemId
                return .auto
            }
    }
}

#Preview(traits: .mockData) {
    ManagedNavigationStack {
        SpaceRootView(restoresState: false)
    }
}
