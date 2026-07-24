// @copyright André Trettin

import CoreRPG
import SwiftUI

struct RuleRootView: View {
    @Environment(RuleRootModel.self) private var root
    private let restoresState: Bool

    init(restoresState: Bool = true) {
        self.restoresState = restoresState
    }

    var body: some View {
        ItemRootView(root: root.rootController)
            .overlay {
                if restoresState {
                    ItemStateRestorationView<RuleRoute, RuleRootModel>(
                        root: root,
                        keyPrefix: "Rule"
                    )
                }
            }
            .onNavigationReceive { (route: RuleRoute, _) in
                guard let itemId = route.detail() else { return .cancel }
                root.navigationModel.selectedItemId = itemId
                return .auto
            }
    }
}

#Preview(traits: .mockData) {
    ManagedNavigationStack {
        RuleRootView(restoresState: false)
    }
}

