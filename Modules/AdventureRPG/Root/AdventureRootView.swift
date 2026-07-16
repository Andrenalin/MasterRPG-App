// @copyright André Trettin

import CoreRPG

import SwiftUI

struct AdventureRootView: View {
    @Environment(AdventureRootModel.self) private var root
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
                    ItemStateRestorationView<AdventureRoute, AdventureRootModel>(root: root, keyPrefix: "Adventure")
                }
            }
            .onNavigationReceive { (route: AdventureRoute, navigator) in
                guard let itemId = route.detail() else { return .cancel }
                if root.folderListController.listModel.selectedItemId == itemId {
                    return .immediately
                }
                root.folderListController.listModel.set(selectedItemId: itemId)
                return .auto
            }
    }
}

#Preview(traits: .mockData) {
    ManagedNavigationStack {
        AdventureRootView(restoresState: false)
    }
}
