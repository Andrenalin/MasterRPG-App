// @copyright André Trettin

import CoreRPG
import SwiftUI

struct CharacterRootView: View {
    @Environment(CharacterRootModel.self) private var root
    @Environment(\.navigator) private var navigator
    private let restoresState: Bool

    init(restoresState: Bool = true) {
        self.restoresState = restoresState
    }

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        
        ItemRootView(root: root.rootController)
            .overlay {
                if restoresState {
                    ItemStateRestorationView<CharacterRoute, CharacterRootModel>(root: root, keyPrefix: "Character")
                }
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
        CharacterRootView(restoresState: false)
    }
}
