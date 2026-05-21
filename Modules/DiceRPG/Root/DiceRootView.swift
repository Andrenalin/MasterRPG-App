// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DiceRootView: View {
    @Environment(DiceRootModel.self) private var root
    @Environment(\.navigator) private var navigator

    var body: some View {
        ItemRootView(root: root.rootController)
            .overlay {
                ItemStateRestorationView<DiceRoute, DiceRootModel>(root: root, keyPrefix: "Dice")
            }
            .onNavigationReceive { (route: DiceRoute, navigator) in
                guard let itemId = route.detail() else { return .cancel }
                root.navigationModel.selectedItemId = itemId
                return .auto
            }
    }
}

#Preview(traits: .mockData) {
    ManagedNavigationStack {
        DiceRootView()
    }
}
