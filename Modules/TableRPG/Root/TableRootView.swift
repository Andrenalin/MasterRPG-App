// @copyright André Trettin

import CoreRPG
import SwiftUI

struct TableRootView: View {
    @Environment(TableRootModel.self) private var root
    @Environment(\.navigator) private var navigator
    private let restoresState: Bool

    init(restoresState: Bool = true) {
        self.restoresState = restoresState
    }

    var body: some View {
        ItemRootView(root: root.rootController)
            .overlay {
                if restoresState {
                    ItemStateRestorationView<TableRoute, TableRootModel>(root: root, keyPrefix: "Table")
                }
            }
            .onNavigationReceive { (route: TableRoute, navigator) in
                guard let itemId = route.detail() else { return .cancel }
                root.navigationModel.selectedItemId = itemId
                return .auto
            }
    }
}

#Preview(traits: .mockData) {
    ManagedNavigationStack {
        TableRootView(restoresState: false)
    }
}
