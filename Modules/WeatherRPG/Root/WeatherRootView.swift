// @copyright André Trettin

import CoreRPG
import SwiftUI

struct WeatherRootView: View {
    @Environment(WeatherRootModel.self) private var root
    @Environment(\.navigator) private var navigator

    var body: some View {
        ItemRootView(root: root.rootController)
            .overlay {
                ItemStateRestorationView<WeatherRoute, WeatherRootModel>(root: root, keyPrefix: "Weather")
            }
            .onNavigationReceive { (route: WeatherRoute, navigator) in
                guard let itemId = route.detail() else { return .cancel }
                root.navigationModel.selectedItemId = itemId
                return .auto
            }
    }
}

#Preview(traits: .mockData) {
    ManagedNavigationStack {
        WeatherRootView()
    }
}
