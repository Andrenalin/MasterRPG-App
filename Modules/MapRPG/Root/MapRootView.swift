// @copyright André Trettin

import CoreRPG
import SwiftUI

struct MapRootView: View {
    @Environment(MapRootModel.self) private var root
    @Environment(\.navigator) private var navigator
    private let restoresState: Bool

    init(restoresState: Bool = true) {
        self.restoresState = restoresState
    }

    var body: some View {
        ItemRootView(root: root.rootController)
            .overlay {
                if restoresState {
                    ItemStateRestorationView<MapRoute, MapRootModel>(root: root, keyPrefix: "Map")
                }
            }
            .onNavigationReceive { (route: MapRoute, navigator) in
                guard let itemId = route.detail() else { return .cancel }
                root.navigationModel.selectedItemId = itemId
                return .auto
            }
    }
}

#Preview(traits: .mockData) {
    ManagedNavigationStack {
        MapRootView(restoresState: false)
    }
}
