// @copyright André Trettin

import CoreRPG
import SwiftUI

struct CharacterRootView: View {
    @Environment(CharacterRootModel.self) private var root
    @Environment(\.navigator) private var navigator

    var body: some View {
        ItemRootView(root: root.rootController)
            .overlay {
                ItemStateRestorationView<CharacterRoute, CharacterRootModel>(root: root, keyPrefix: "Character")
            }
            .onNavigationReceive { (route: CharacterRoute, navigator) in
                guard let itemId = route.detail() else { return .cancel }
                root.navigationModel.selectedItemId = itemId
                return .auto
            }
    }
}

#Preview(traits: .mockData) {
    ManagedNavigationStack {
        CharacterRootView()
    }
}
